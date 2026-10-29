import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/owned_temp.dart';

import 'resume_refresh_test.dart'
    show ResumeFixture, ResumeBackground, NoResumeUpdates;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory folder;
  var process = 'process-before-close';
  final repos = <FamilyRepository>[];
  Map<String, dynamic> data(String actor, int coins) => {
    'user': {'id': actor, 'role': actor == 'kid' ? 'child' : 'parent'},
    'balance': {'total': coins, 'available': coins - 5, 'reserved': 5},
    'tasks': [
      {'id': 'task', 'status': coins == 10 ? 'submitted' : 'approved'},
    ],
    'rooms': [
      {'id': 'room', 'unread_count': coins == 10 ? 2 : 0},
    ],
    'rewards': [
      {'id': 'gift', 'price': coins},
    ],
    'redemptions': [
      {'id': 'request', 'status': 'issued'},
    ],
    'penalties': [
      {'id': 'fine', 'status': 'confirmed'},
    ],
    'grades': [
      {'id': 'grade', 'value': 5},
    ],
    'schedules': [
      {'id': 'event', 'version': coins},
    ],
  };
  http.Response reply(Object body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('mykids-cold-start-');
    await databaseFactory.setDatabasesPath(folder.path);
    FlutterSecureStorage.setMockInitialValues({
      'session': 'synthetic-cold-start',
      'endpoint': 'https://family.example',
    });
    process = 'process-before-close';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('ru.mykids/runtime'),
      (call) async => call.method == 'androidSdkInt' ? 36 : process,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => folder.path,
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    for (final repo in repos) {
      if (repo.db!.isOpen) await repo.db!.close();
      repo.client.close();
      repo.dispose();
    }
    repos.clear();
    if (!folder.path.startsWith(Directory.systemTemp.path) ||
        !folder.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('mykids-cold-start-')) {
      throw StateError('Unexpected test folder');
    }
    await deleteOwnedTestTemp(folder);
  });
  Future<FamilyRepository> open(http.Client client) async {
    final repo = FamilyRepository(client: client);
    repos.add(repo);
    await repo.initialize();
    return repo;
  }

  Future<void> save(FamilyRepository repo, String actor) async {
    await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
    repo.snapshot = data(actor, 10);
    await repo.cache(repo.snapshot!);
  }

  Future<void> queue(
    FamilyRepository repo, {
    List<String> files = const [],
  }) async {
    // This FFI fixture tests queue persistence, not native scheduler registration.
    final platform = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await repo.mutate(
        '/v1/tasks/task/submissions',
        {'task_version': 1},
        files: files,
        offlineSubmission: true,
      );
    } finally {
      debugDefaultTargetPlatformOverride = platform;
    }
  }

  for (final actor in ['kid', 'papa', 'mama']) {
    test(
      '$actor retains cached data offline and fetches fresh data after reopening',
      () async {
        final before = await open(MockClient((_) async => reply({})));
        await save(before, actor);
        await before.db!.close();
        process = 'process-after-reboot';
        var connected = false;
        final after = await open(
          MockClient((_) async {
            if (!connected) throw const SocketException('Offline');
            return reply(data(actor, 75));
          }),
        );
        expect(after.signedIn, true);
        expect(after.snapshot, data(actor, 10));
        await after.sync();
        expect(after.snapshot, data(actor, 10));
        connected = true;
        await after.reconnect();
        expect(after.snapshot, data(actor, 75));
        expect(after.online, true);
      },
    );
    test(
      '$actor immediately retries a dead process lease using the original operation key',
      () async {
        final before = await open(MockClient((_) async => reply({})));
        await save(before, actor);
        await queue(before);
        final row = (await before.pending()).single;
        await before.db!.update('outbox', {
          'lease_owner': process,
          'lease_until': DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        });
        await before.db!.close();
        process = 'process-after-kill';
        final keys = <String?>[];
        final after = await open(
          MockClient((request) async {
            if (request.method == 'GET') return reply(data(actor, 75));
            keys.add(request.headers['Idempotency-Key']);
            return reply({'already_applied': true});
          }),
        );
        await after.sync();
        expect(keys, [row['id']]);
        expect(await after.pending(), isEmpty);
        expect(after.snapshot, data(actor, 75));
      },
    );
    testWidgets(
      '$actor refreshes while notification initialization is still waiting',
      (tester) async {
        final gate = Completer<void>();
        final repo = ResumeFixture(actor == 'kid' ? 'child' : 'parent');
        final background = ResumeBackground(repo)..initialization = gate;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          MyKidsApp(
            repository: repo,
            createBackground: (_) => background,
            createUpdates: NoResumeUpdates.new,
            now: () => DateTime.utc(2026, 10, 16, 12),
          ),
        );
        await tester.pumpAndSettle();
        expect(repo.syncs, greaterThanOrEqualTo(1));
        final first = repo.syncs;
        await tester.pump(const Duration(seconds: 3));
        expect(repo.syncs, greaterThan(first));
        await tester.pumpWidget(const SizedBox.shrink());
        gate.complete();
        await tester.pump();
        repo.client.close();
        repo.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'two repositories in the live process retain the same exclusive lease',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var writes = 0;
      final before = await open(
        MockClient((request) async {
          if (request.method == 'GET') return reply(data('kid', 10));
          writes++;
          started.complete();
          await release.future;
          return reply({'ok': true});
        }),
      );
      await save(before, 'kid');
      await queue(before);
      final first = before.sync();
      await started.future;
      final background = await open(
        MockClient((request) async {
          if (request.method != 'GET') writes++;
          return reply(data('kid', 10));
        }),
      );
      await background.sync();
      expect(writes, 1);
      expect(await background.pending(), hasLength(1));
      release.complete();
      await first;
      expect(await before.pending(), isEmpty);
    },
  );
  for (final corrupt in [
    '{"user":',
    '[]',
    'null',
    '{}',
    '{"user":[]}',
    '{"user":{"role":"admin"}}',
  ]) {
    test(
      'damaged cache $corrupt preserves identity, queued action and photos',
      () async {
        final before = await open(MockClient((_) async => reply({})));
        await save(before, 'kid');
        final photo = File('${folder.path}/page.jpg');
        await photo.writeAsBytes([1, 2, 3]);
        await queue(before, files: [photo.path]);
        await before.db!.update('cache', {'data': corrupt});
        await before.db!.close();
        final after = await open(
          MockClient((_) async => reply(data('kid', 75))),
        );
        expect(after.signedIn, true);
        expect(after.snapshot, isNull);
        expect(await after.pending(), hasLength(1));
        expect(await photo.readAsBytes(), [1, 2, 3]);
        expect(await after.db!.query('cache'), isEmpty);
        // Authenticate and rebuild the replaceable cache without replaying the
        // synthetic photo, whose bytes intentionally are not a real JPEG.
        await after.db!.update('outbox', {'state': 'failed'});
        await after.sync();
        expect(after.snapshot, data('kid', 75));
      },
    );
  }
  test(
    'version two upgrade retains all data and recovers the old unowned lease',
    () async {
      final legacy = await openDatabase(
        '${folder.path}/family.sqlite',
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE cache(id INTEGER PRIMARY KEY,data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE identity(id INTEGER PRIMARY KEY,tag TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE outbox(id TEXT PRIMARY KEY,path TEXT NOT NULL,method TEXT NOT NULL,body TEXT NOT NULL,files TEXT NOT NULL,state TEXT NOT NULL,error TEXT,lease_until INTEGER NOT NULL DEFAULT 0,auth_tag TEXT NOT NULL)',
          );
        },
      );
      final tag = FamilyRepository()..token = 'synthetic-cold-start';
      await legacy.insert('identity', {'id': 1, 'tag': tag.sessionTag});
      await legacy.insert('cache', {
        'id': 1,
        'data': jsonEncode(data('kid', 10)),
      });
      await legacy.insert('outbox', {
        'id': 'kept-command',
        'path': '/v1/tasks/task/submissions',
        'method': 'POST',
        'body': '{"task_version":1}',
        'files': '[]',
        'state': 'pending',
        'auth_tag': tag.sessionTag,
        'lease_until': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
      tag.client.close();
      tag.dispose();
      await legacy.close();
      final keys = <String?>[];
      final after = await open(
        MockClient((request) async {
          if (request.method == 'GET') return reply(data('kid', 75));
          keys.add(request.headers['Idempotency-Key']);
          return reply({'ok': true});
        }),
      );
      expect(after.snapshot, data('kid', 10));
      expect(await after.db!.getVersion(), 3);
      await after.sync();
      expect(keys, ['kept-command']);
      expect(await after.pending(), isEmpty);
    },
  );
}
