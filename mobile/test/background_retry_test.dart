import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/background.dart';
import 'package:workmanager/workmanager.dart';

class RetryWorkmanager extends WorkmanagerPlatform {
  final registrations = <Map<String, Object?>>[];

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
    registrations.add({
      'name': uniqueName,
      'task': taskName,
      'network': constraints?.networkType,
      'policy': existingWorkPolicy,
      'backoff': backoffPolicy,
      'delay': backoffPolicyDelay,
      'input': inputData,
      'expedited': expedited,
      'quota': outOfQuotaPolicy,
      'foreground': ?foregroundServiceConfig,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RetryWorkmanager jobs;
  late WorkmanagerPlatform original;
  final shown = <Map<dynamic, dynamic>>[];
  const notificationChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    FlutterSecureStorage.setMockInitialValues({
      'session': 'synthetic-retry-session',
    });
    original = WorkmanagerPlatform.instance;
    jobs = RetryWorkmanager();
    WorkmanagerPlatform.instance = jobs;
    shown.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('ru.mykids/runtime'),
          (call) async => call.method == 'androidSdkInt' ? 36 : false,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'show') shown.add(call.arguments as Map);
          return null;
        });
    // A delivered callback must not open SQLite or wait for a network response.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'), (
          _,
        ) async {
          fail('The FCM callback must delegate data loading to durable work');
        });
  });
  tearDown(() {
    WorkmanagerPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'visible push persists refresh before its short callback finishes',
    () async {
      await incomingPush(
        const RemoteMessage(messageId: 'money', data: {'kind': 'money'}),
      ).timeout(const Duration(seconds: 2));
      expect(jobs.registrations.single, {
        'name': 'mykids-push-urgent',
        'task': 'family-sync',
        'network': NetworkType.connected,
        'policy': ExistingWorkPolicy.append,
        'backoff': BackoffPolicy.exponential,
        'delay': const Duration(seconds: 30),
        'input': null,
        'expedited': true,
        'quota': OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
      });
      expect(shown, hasLength(1));
    },
  );
  test(
    'silent calendar queues data loading without showing an alert',
    () async {
      await incomingPush(
        const RemoteMessage(messageId: 'calendar', data: {'kind': 'calendar'}),
      );
      expect(jobs.registrations, hasLength(1));
      expect(jobs.registrations.single['name'], 'mykids-push-retry');
      expect(jobs.registrations.single['expedited'], false);
      expect(shown, isEmpty);
    },
  );
  test('a pending calendar refresh cannot hold up a visible push', () async {
    await incomingPush(
      const RemoteMessage(messageId: 'quiet-first', data: {'kind': 'calendar'}),
    );
    await incomingPush(
      const RemoteMessage(messageId: 'urgent-second', data: {'kind': 'money'}),
    );
    expect(jobs.registrations, hasLength(2));
    expect(jobs.registrations[0]['name'], 'mykids-push-retry');
    expect(jobs.registrations[0]['expedited'], false);
    expect(jobs.registrations[1]['name'], 'mykids-push-urgent');
    expect(jobs.registrations[1]['expedited'], true);
    expect(shown, hasLength(1));
  });
  test(
    'Data Saver uses visible sync while retaining connected fallback',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ru.mykids/runtime'),
            (call) async => call.method == 'androidSdkInt' ? 36 : true,
          );
      await incomingPush(
        const RemoteMessage(messageId: 'metered', data: {'kind': 'money'}),
      );
      expect(jobs.registrations, hasLength(2));
      expect(jobs.registrations[0]['name'], 'mykids-push-urgent');
      expect(jobs.registrations[0]['network'], NetworkType.connected);
      final visible = jobs.registrations[1];
      expect(visible['name'], 'mykids-push-metered');
      expect(visible['network'], NetworkType.notRequired);
      expect(visible['expedited'], true);
      final info = visible['foreground'] as ForegroundServiceConfig;
      expect(info.foregroundServiceType, ForegroundServiceType.dataSync);
      expect(info.notificationText, 'Обновляем семейные данные');
      expect(shown, hasLength(1));
    },
  );
  test(
    'a notification burst retains every invalidation without cancelling work',
    () async {
      await Future.wait(
        List.generate(
          3,
          (i) => incomingPush(
            RemoteMessage(
              messageId: 'burst-$i',
              data: const {'kind': 'message'},
            ),
          ),
        ),
      );
      expect(jobs.registrations, hasLength(3));
      expect(
        jobs.registrations.every(
          (r) => r['policy'] == ExistingWorkPolicy.append,
        ),
        true,
      );
      expect(jobs.registrations.every((r) => r['input'] == null), true);
    },
  );
  test(
    'a signed-out device neither schedules family work nor reveals an alert',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      await incomingPush(
        const RemoteMessage(messageId: 'signed-out', data: {'kind': 'message'}),
      );
      expect(jobs.registrations, isEmpty);
      expect(shown, isEmpty);
    },
  );
  test(
    'native call pushes do not enter the ordinary family refresh queue',
    () async {
      for (final kind in ['call', 'call_state']) {
        await incomingPush(
          RemoteMessage(messageId: kind, data: {'kind': kind}),
        );
      }
      expect(jobs.registrations, isEmpty);
      expect(shown, isEmpty);
    },
  );
  test('generic alerts never copy private message contents', () async {
    await incomingPush(
      const RemoteMessage(
        messageId: 'private',
        data: {'kind': 'message', 'text': 'private family contents'},
      ),
    );
    expect(shown.single['body'], 'Есть новые семейные события');
    expect(shown.single.values, isNot(contains('private family contents')));
  });
  test(
    'older Android keeps a durable job without requiring a foreground service',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ru.mykids/runtime'),
            (call) async => call.method == 'androidSdkInt' ? 30 : false,
          );
      await incomingPush(
        const RemoteMessage(
          messageId: 'old-android',
          data: {'kind': 'message'},
        ),
      );
      expect(jobs.registrations.single['expedited'], false);
      expect(
        jobs.registrations.single['quota'],
        OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
      );
    },
  );
  test('an unavailable native SDK probe cannot drop the refresh', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('ru.mykids/runtime'),
          (_) async => throw MissingPluginException(),
        );
    await incomingPush(
      const RemoteMessage(
        messageId: 'legacy-bridge',
        data: {'kind': 'message'},
      ),
    );
    expect(jobs.registrations.single['expedited'], false);
  });
}
