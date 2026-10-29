import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/outbox_sync.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmanager/workmanager.dart';

import 'support/owned_temp.dart';

class _Jobs extends WorkmanagerPlatform {
  final requests = <Map<String, Object?>>[];
  Future<void> Function()? beforeEnqueue;
  bool unavailable = false;
  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    await beforeEnqueue?.call();
    if (unavailable) throw PlatformException(code: 'temporarily_unavailable');
    requests.add({
      'name': uniqueName,
      'task': taskName,
      'network': constraints?.networkType,
      'policy': existingWorkPolicy,
      'initialDelay': initialDelay,
      'expedited': expedited,
      'quota': outOfQuotaPolicy,
      'backoff': backoffPolicy,
      'retryDelay': backoffPolicyDelay,
      'input': inputData,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory folder;
  late FamilyRepository repo;
  late _Jobs jobs;
  late WorkmanagerPlatform original;
  const runtime = MethodChannel('ru.mykids/runtime');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var sdk = 36;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    folder = await Directory.systemTemp.createTemp('mykids-immediate-');
    await databaseFactory.setDatabasesPath(folder.path);
    FlutterSecureStorage.setMockInitialValues({
      'session': 'synthetic-outbox-session',
      'endpoint': 'https://family.example',
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => folder.path,
    );
    sdk = 36;
    messenger.setMockMethodCallHandler(
      runtime,
      (call) async => call.method == 'androidSdkInt' ? sdk : 'test-process',
    );
    original = WorkmanagerPlatform.instance;
    jobs = _Jobs();
    WorkmanagerPlatform.instance = jobs;
    repo = FamilyRepository(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await repo.initialize('child');
    await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
  });
  tearDown(() async {
    await repo.db?.close();
    repo.client.close();
    repo.dispose();
    WorkmanagerPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(runtime, null);
    expect(folder.parent.path, Directory.systemTemp.path);
    expect(
      folder.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('mykids-immediate-'),
      isTrue,
    );
    await deleteOwnedTestTemp(folder);
  });

  test(
    'offline photos are committed before connected work is persisted',
    () async {
      final photos = [
        for (var i = 0; i < 2; i++)
          await File('${folder.path}/page$i.jpg').writeAsBytes([i, 2, 3]),
      ];
      jobs.beforeEnqueue = () async {
        final row = (await repo.pending()).single;
        expect(
          jsonDecode(row['files'] as String),
          photos.map((f) => f.path).toList(),
        );
        expect(row['auth_tag'], repo.sessionTag);
      };
      expect(
        (await repo.mutate(
          '/v1/tasks/task/submissions',
          {},
          offlineSubmission: true,
          files: photos.map((f) => f.path).toList(),
        ))['queued'],
        isTrue,
      );
      expect(jobs.requests.single, {
        'name': 'mykids-outbox',
        'task': 'family-sync',
        'network': NetworkType.connected,
        'policy': ExistingWorkPolicy.append,
        'initialDelay': null,
        'expedited': true,
        'quota': OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
        'backoff': BackoffPolicy.exponential,
        'retryDelay': const Duration(seconds: 30),
        'input': null,
      });
      expect(photos.every((f) => f.existsSync()), isTrue);
    },
  );

  test('every new command appends a refresh rather than losing it behind running work', () async {
    await repo.mutate('/v1/tasks/a/plan', {}, offlineSubmission: true);
    await repo.mutate('/v1/tasks/b/plan', {}, offlineSubmission: true);
    expect((await repo.pending()).length, 2);
    expect(jobs.requests.length, 2);
    expect(
      jobs.requests.every((r) => r['policy'] == ExistingWorkPolicy.append),
      isTrue,
    );
  });

  test(
    'scheduler failure preserves the saved action and its retry identity',
    () async {
      jobs.unavailable = true;
      expect(
        (await repo.mutate(
          '/v1/tasks/task/plan',
          {},
          offlineSubmission: true,
        ))['queued'],
        isTrue,
      );
      final before = (await repo.pending()).single;
      jobs.unavailable = false;
      await queueOutboxSync();
      expect((await repo.pending()).single, before);
      expect(jobs.requests.length, 1);
    },
  );

  test(
    'a connection lost during an online action schedules automatic retry',
    () async {
      await repo.db!.close();
      repo.client.close();
      repo = FamilyRepository(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await repo.initialize('child');
      repo.online = true;
      expect(
        (await repo.mutate(
          '/v1/tasks/task/plan',
          {},
          offlineSubmission: true,
        ))['queued'],
        isTrue,
      );
      expect(jobs.requests.length, 1);
      expect((await repo.pending()).single['state'], 'pending');
    },
  );

  test('temporary server rejection retains work and schedules retry', () async {
    await repo.db!.close();
    repo.client.close();
    repo = FamilyRepository(
      client: MockClient(
        (_) async => http.Response('{"detail":"temporary"}', 503),
      ),
    );
    await repo.initialize('child');
    repo.online = true;
    await expectLater(
      repo.mutate('/v1/tasks/task/plan', {}),
      throwsA(isA<ApiFailure>()),
    );
    expect(jobs.requests.length, 1);
    expect((await repo.pending()).single['state'], 'pending');
  });

  test('older Android retains connected work without unsupported expedited service', () async {
    sdk = 30;
    await queueOutboxSync();
    expect(jobs.requests.single['expedited'], isFalse);
    expect(jobs.requests.single['network'], NetworkType.connected);
  });

  test('optional SDK failure still persists ordinary connected work', () async {
    messenger.setMockMethodCallHandler(
      runtime,
      (_) async => throw PlatformException(code: 'probe_unavailable'),
    );
    await queueOutboxSync();
    expect(jobs.requests.single['expedited'], isFalse);
  });

  test('offline actions requiring internet do not enter the queue', () async {
    await expectLater(
      repo.mutate('/v1/redemptions', {}),
      throwsA(isA<ApiFailure>()),
    );
    expect(await repo.pending(), isEmpty);
    expect(jobs.requests, isEmpty);
  });
}
