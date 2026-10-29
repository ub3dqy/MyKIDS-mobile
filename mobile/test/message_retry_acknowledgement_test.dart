import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  final snapshot = <String, dynamic>{
    'user': {'id': 'child', 'role': 'child'},
    'rooms': [
      {'id': 'chat', 'unread_count': 0},
    ],
    'tasks': [],
    'schedules': [],
    'grades': [],
    'rewards': [],
    'redemptions': [],
    'penalties': [],
  };
  http.Response reply(Map<String, dynamic> value) =>
      http.Response.bytes(utf8.encode(jsonEncode(value)), 200);

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    repositories.clear();
    folder = await Directory.systemTemp.createTemp('mykids-message-retry-');
    await databaseFactory.setDatabasesPath(folder.path);
    FlutterSecureStorage.setMockInitialValues({
      'session': 'synthetic-message-session',
      'endpoint': 'https://family.example',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => folder.path,
        );
  });
  tearDown(() async {
    for (final repository in repositories) {
      await repository.db?.close();
      repository.client.close();
      repository.dispose();
    }
    debugDefaultTargetPlatformOverride = null;
    expect(folder.parent.path, Directory.systemTemp.path);
    expect(
      folder.path.split(Platform.pathSeparator).last,
      startsWith('mykids-message-retry-'),
    );
    await deleteOwnedTestTemp(folder);
  });
  Future<FamilyRepository> create(http.Client client) async {
    final repository = FamilyRepository(client: client);
    repositories.add(repository);
    await repository.initialize('child');
    await repository.db!.insert('identity', {
      'id': 1,
      'tag': repository.sessionTag,
    });
    repository.snapshot = snapshot;
    await repository.cache(snapshot);
    return repository;
  }

  test(
    'a saved message is acknowledged when its server reply is lost',
    () async {
      var unavailable = true;
      var notifications = 0;
      final requestKeys = <String>[];
      final accepted = <String, Map<String, dynamic>>{};
      final repository = await create(
        MockClient((request) async {
          if (request.method == 'GET') return reply(snapshot);
          expect(request.url.path, '/v1/rooms/chat/messages');
          final key = request.headers['Idempotency-Key']!;
          requestKeys.add(key);
          final message = accepted.putIfAbsent(
            key,
            () => {
              'id': 'saved-message',
              'text': (jsonDecode(request.body) as Map)['text'],
            },
          );
          // The server committed the message, but its first acknowledgement failed.
          if (unavailable) {
            return http.Response('{"detail":"Temporarily unavailable"}', 503);
          }
          return reply(message);
        }),
      );
      repository.online = true;
      repository.addListener(() => notifications++);
      final result = await repository.mutate('/v1/rooms/chat/messages', {
        'text': 'Привет, бабушка!',
      });
      expect(result['queued'], isTrue);
      expect(repository.online, isFalse);
      expect(notifications, greaterThan(0));
      final pending = (await repository.pending()).single;
      expect(pending['state'], 'pending');
      expect(jsonDecode(pending['body'] as String), {
        'text': 'Привет, бабушка!',
      });
      expect(accepted, hasLength(1));

      unavailable = false;
      await repository.sync();
      expect(await repository.pending(), isEmpty);
      expect(requestKeys, hasLength(2));
      expect(requestKeys[1], requestKeys[0]);
      expect(accepted, hasLength(1));
      await repository.sync();
      expect(requestKeys, hasLength(2));
    },
  );

  test(
    'known offline text keeps the existing explicit network requirement',
    () async {
      var requests = 0;
      final repository = await create(
        MockClient((request) async {
          requests++;
          return reply({});
        }),
      );
      repository.online = false;
      await expectLater(
        repository.mutate('/v1/rooms/chat/messages', {'text': 'Черновик'}),
        throwsA(
          isA<ApiFailure>().having((error) => error.status, 'status', 503),
        ),
      );
      expect(await repository.pending(), isEmpty);
      expect(requests, 0);
    },
  );

  test(
    'financial server uncertainty still raises and retains its command',
    () async {
      final repository = await create(
        MockClient((request) async {
          if (request.method == 'GET') return reply(snapshot);
          return http.Response('{"detail":"Temporarily unavailable"}', 503);
        }),
      );
      repository.online = true;
      await expectLater(
        repository.mutate('/v1/redemptions', {'reward_id': 'gift'}),
        throwsA(
          isA<ApiFailure>().having((error) => error.status, 'status', 503),
        ),
      );
      final pending = (await repository.pending()).single;
      expect(pending['path'], '/v1/redemptions');
      expect(pending['state'], 'pending');
    },
  );
}
