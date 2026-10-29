import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/owned_temp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory folder;
  final repositories = <FamilyRepository>[];
  final alive = <String>{};
  var owner = 'engine-a';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    folder = await Directory.systemTemp.createTemp('mykids-engine-retry-');
    await databaseFactory.setDatabasesPath(folder.path);
    FlutterSecureStorage.setMockInitialValues({
      'session': 'synthetic-engine-session',
      'endpoint': 'https://family.example',
    });
    owner = 'engine-a';
    alive
      ..clear()
      ..add(owner);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => folder.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('ru.mykids/runtime'),
      (call) async {
        if (call.method == 'androidSdkInt') return 36;
        if (call.method == 'outboxOwnerAlive') {
          return alive.contains((call.arguments as Map)['owner']);
        }
        return owner;
      },
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    for (final repo in repositories) {
      if (repo.db!.isOpen) await repo.db!.close();
      repo.client.close();
      repo.dispose();
    }
    repositories.clear();
    messenger.setMockMethodCallHandler(
      const MethodChannel('ru.mykids/runtime'),
      null,
    );
    expect(folder.parent.path, Directory.systemTemp.path);
    expect(
      folder.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('mykids-engine-retry-'),
      isTrue,
    );
    await deleteOwnedTestTemp(folder);
  });
  Future<FamilyRepository> open(http.Client client) async {
    final repo = FamilyRepository(client: client);
    repositories.add(repo);
    await repo.initialize();
    return repo;
  }

  for (final detached in [false, true]) {
    test('another engine reclaims only a detached sender: $detached', () async {
      final first = await open(
        MockClient((_) async => http.Response('{}', 200)),
      );
      await first.db!.insert('identity', {'id': 1, 'tag': first.sessionTag});
      await first.mutate('/v1/tasks/task/submissions', {
        'task_version': 1,
      }, offlineSubmission: true);
      final command = (await first.pending()).single;
      await first.db!.update('outbox', {
        'lease_owner': owner,
        'lease_until': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
      if (detached) alive.remove(owner);
      owner = 'engine-b';
      alive.add(owner);
      final keys = <String?>[];
      final next = await open(
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'user': {'id': 'kid', 'role': 'child'},
                'balance': {'total': 75},
              }),
              200,
            );
          }
          keys.add(request.headers['Idempotency-Key']);
          return http.Response('{}', 200);
        }),
      );
      await next.sync();
      expect(keys, detached ? [command['id']] : isEmpty);
      expect(await next.pending(), detached ? isEmpty : hasLength(1));
    });
  }
  test('an old reply cannot delete a new sender queue or its photo', () async {
    late FamilyRepository repo;
    repo = await open(
      MockClient((request) async {
        if (request.url.path == '/v1/attachments') {
          return http.Response('{"id":"page"}', 200);
        }
        await repo.db!.update('outbox', {'lease_owner': 'engine-b'});
        return http.Response('{}', 200);
      }),
    );
    await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
    final photo = await File('${folder.path}/page.png').writeAsBytes([1, 2, 3]);
    await repo.mutate(
      '/v1/tasks/task/submissions',
      {'task_version': 1},
      offlineSubmission: true,
      files: [photo.path],
    );
    await repo.sendOutbox((await repo.pending()).single);
    expect((await repo.pending()).single['lease_owner'], 'engine-b');
    expect(await photo.exists(), isTrue);
  });
}
