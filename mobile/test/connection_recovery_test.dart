import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/owned_temp.dart';

class RecoveryServices extends BackgroundServices {
  int registrations = 0, alarms = 0;
  RecoveryServices(super.repository);
  @override
  Future<void> registerDevice() async => registrations++;
  @override
  Future<void> reminders() async => alarms++;
}

class HeldClient extends http.BaseClient {
  final started = Completer<void>();
  int requests = 0;
  final Map<String, dynamic> fresh;
  HeldClient(this.fresh);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (requests++ == 0) {
      started.complete();
      await (request as http.Abortable).abortTrigger;
      throw http.RequestAbortedException(request.url);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(fresh))),
      200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory folder;
  final repos = <FamilyRepository>[];
  final services = <RecoveryServices>[];
  Map<String, dynamic> data(String role, {int amount = 0}) => {
    'user': {'id': role, 'role': role},
    'balance': {'total': amount, 'available': amount, 'reserved': 0},
    'tasks': [
      {'id': 'task', 'status': amount == 0 ? 'submitted' : 'approved'},
    ],
    'rooms': [
      {'id': 'chat', 'unread_count': amount == 0 ? 2 : 0},
    ],
    'redemptions': [],
    'penalties': [],
    'grades': [],
    'schedules': [],
    'rewards': [
      {'id': 'gift', 'price': amount == 0 ? 25 : 60},
    ],
  };
  http.Response reply(Map<String, dynamic> value) =>
      http.Response.bytes(utf8.encode(jsonEncode(value)), 200);
  setUp(() async {
    // FFI reconnection tests do not install Android's native job scheduler.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    repos.clear();
    services.clear();
    folder = await Directory.systemTemp.createTemp('mykids-reconnect-');
    await databaseFactory.setDatabasesPath(folder.path);
    FlutterSecureStorage.setMockInitialValues({
      'session': 'synthetic-reconnect-token',
      'endpoint': 'https://family.example',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => folder.path,
        );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    for (final value in services) {
      value.dispose();
    }
    for (final repo in repos) {
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
    }
    if (!folder.path.startsWith(Directory.systemTemp.path) ||
        !folder.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('mykids-reconnect-')) {
      throw StateError('Unexpected test folder');
    }
    await deleteOwnedTestTemp(folder);
  });
  Future<FamilyRepository> create(http.Client client, String role) async {
    final repo = FamilyRepository(client: client);
    repos.add(repo);
    await repo.initialize(role);
    await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
    repo.snapshot = data(role);
    await repo.cache(repo.snapshot!);
    return repo;
  }

  Future<void> queue(FamilyRepository repo) async {
    await repo.mutate('/v1/tasks/task/submissions', {
      'task_version': 1,
      'marked_at': '2026-10-16T12:00:00Z',
    }, offlineSubmission: true);
  }

  for (final role in ['parent', 'child', 'relative']) {
    for (final failure in ['server', 'socket', 'timeout', 'client', 'tls']) {
      test(
        '$role refreshes all data despite a $failure outbox retry',
        () async {
          var fail = true, writes = 0;
          final keys = <String?>[];
          final fresh = data(role, amount: 50);
          final repo = await create(
            MockClient((request) async {
              if (request.method == 'GET') return reply(fresh);
              writes++;
              keys.add(request.headers['Idempotency-Key']);
              if (fail) {
                switch (failure) {
                  case 'server':
                    return http.Response('{"detail":"Retry later"}', 503);
                  case 'socket':
                    throw const SocketException('Disconnected');
                  case 'timeout':
                    throw TimeoutException('Connection changed');
                  case 'tls':
                    throw HandshakeException('Connection interrupted');
                  default:
                    throw http.ClientException('Disconnected');
                }
              }
              return http.Response('{"ok":true}', 200);
            }),
            role,
          );
          await queue(repo);
          await repo.reconnect();
          expect(repo.online, isTrue);
          expect(repo.snapshot, fresh);
          expect((await repo.pending()).single['state'], 'pending');
          expect(
            jsonDecode(
              (await repo.db!.query('cache')).single['data'] as String,
            ),
            fresh,
          );
          fail = false;
          await repo.sync();
          expect(await repo.pending(), isEmpty);
          expect(writes, 2);
          expect(keys[0], keys[1]);
        },
      );
    }
  }
  test(
    'reconnect aborts the old transport before refreshing the open session',
    () async {
      final fresh = data('child', amount: 50);
      final client = HeldClient(fresh);
      final repo = await create(client, 'child');
      final identity = repo.sessionTag;
      final previous = repo.sync();
      await client.started.future;
      await repo.reconnect().timeout(const Duration(seconds: 2));
      await previous;
      expect(repo.snapshot, fresh);
      expect(repo.online, isTrue);
      expect(repo.sessionTag, identity);
      expect(repo.syncing, isFalse);
    },
  );
  test(
    'network loss releases the transport and preserves cached data',
    () async {
      final client = HeldClient(data('child', amount: 50));
      final repo = await create(client, 'child');
      final previous = repo.sync();
      await client.started.future;
      repo.connectionLost();
      await previous.timeout(const Duration(seconds: 2));
      expect(repo.online, isFalse);
      expect(repo.snapshot, data('child'));
      await repo.reconnect();
      expect(repo.online, isTrue);
      expect(repo.snapshot!['balance']['total'], 50);
    },
  );
  test(
    'connectivity events recover the retained repository and refresh alarms',
    () async {
      final repo = await create(
        MockClient((_) async => reply(data('parent', amount: 50))),
        'parent',
      );
      final background = RecoveryServices(repo);
      services.add(background);
      final changes = StreamController<List<ConnectivityResult>>();
      background.watchConnectivity(changes: changes.stream);
      await background.handleConnectivity([ConnectivityResult.none]);
      expect(repo.online, isFalse);
      changes.add([ConnectivityResult.wifi]);
      for (var i = 0; i < 100 && background.alarms == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(repo.online, isTrue);
      expect(repo.snapshot!['balance']['total'], 50);
      expect(background.registrations, 1);
      expect(background.alarms, 1);
      await changes.close();
    },
  );
  test(
    'connected radio with no Internet keeps cached values and pending commands',
    () async {
      final repo = await create(
        MockClient((_) async => throw const SocketException('No Internet')),
        'child',
      );
      await queue(repo);
      final background = RecoveryServices(repo);
      services.add(background);
      await background.handleConnectivity([
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
      ]);
      expect(repo.online, isFalse);
      expect(repo.snapshot, data('child'));
      expect((await repo.pending()).single['state'], 'pending');
      expect(background.alarms, 0);
      expect(background.registrations, 0);
    },
  );
  test(
    'expired access on reconnect clears old data instead of restoring counters',
    () async {
      final repo = await create(
        MockClient((_) async => http.Response('{"detail":"Expired"}', 401)),
        'parent',
      );
      await queue(repo);
      await repo.reconnect();
      expect(repo.signedIn, isFalse);
      expect(repo.snapshot, isNull);
      expect(await repo.db!.query('outbox'), isEmpty);
      expect(await repo.db!.query('cache'), isEmpty);
    },
  );
  test(
    'a leased earlier command preserves send order without blocking reads',
    () async {
      final writes = <String>[];
      final repo = await create(
        MockClient((request) async {
          if (request.method == 'GET') return reply(data('child', amount: 50));
          writes.add(request.headers['Idempotency-Key']!);
          return http.Response('{"ok":true}', 200);
        }),
        'child',
      );
      await queue(repo);
      await queue(repo);
      final pending = await repo.pending();
      await repo.db!.update(
        'outbox',
        {
          'lease_until': DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        },
        where: 'id=?',
        whereArgs: [pending.first['id']],
      );
      await repo.reconnect();
      expect(writes, isEmpty);
      expect(repo.snapshot!['balance']['total'], 50);
      expect(await repo.pending(), hasLength(2));
      await repo.db!.update('outbox', {'lease_until': 0});
      await repo.sync();
      expect(writes, pending.map((r) => r['id']).toList());
      expect(await repo.pending(), isEmpty);
    },
  );
  test('TLS loss keeps the accepted command key and recovers without weakening security', () async {
    var disconnected = true;
    final keys = <String?>[];
    final repo = await create(
      MockClient((request) async {
        if (request.method != 'GET') {
          keys.add(request.headers['Idempotency-Key']);
        }
        if (disconnected) throw HandshakeException('Connection interrupted');
        return reply(
          request.method == 'GET' ? data('child', amount: 50) : {'ok': true},
        );
      }),
      'child',
    );
    repo.online = true;
    final result = await repo.mutate('/v1/tasks/task/submissions', {
      'task_version': 1,
    }, offlineSubmission: true);
    expect(result['queued'], isTrue);
    await repo.reconnect();
    expect(repo.online, isFalse);
    expect((await repo.pending()).single['state'], 'pending');
    disconnected = false;
    await repo.reconnect();
    expect(repo.online, isTrue);
    expect(repo.snapshot!['balance']['total'], 50);
    expect(await repo.pending(), isEmpty);
    expect(keys.toSet(), hasLength(1));
  });
  test(
    'missing saved photo reports the action failure and still refreshes money',
    () async {
      var writes = 0;
      final repo = await create(
        MockClient((request) async {
          if (request.method != 'GET') writes++;
          return reply(data('child', amount: 50));
        }),
        'child',
      );
      await repo.mutate(
        '/v1/tasks/task/submissions',
        {'task_version': 1},
        offlineSubmission: true,
        files: ['${folder.path}${Platform.pathSeparator}missing.jpg'],
      );
      await repo.reconnect();
      expect(repo.online, isTrue);
      expect(repo.snapshot!['balance']['total'], 50);
      final row = (await repo.pending()).single;
      expect(row['state'], 'failed');
      expect(row['error'], contains('Прикрепите фото повторно'));
      expect(writes, 0);
    },
  );
  test(
    'disposed connectivity watcher cannot refresh or change online state',
    () async {
      var calls = 0;
      final repo = await create(
        MockClient((_) async {
          calls++;
          return reply(data('parent'));
        }),
        'parent',
      );
      final background = RecoveryServices(repo);
      background.dispose();
      repo.online = true;
      await background.handleConnectivity([ConnectivityResult.none]);
      await background.handleConnectivity([ConnectivityResult.mobile]);
      expect(repo.online, isTrue);
      expect(calls, 0);
    },
  );
}
