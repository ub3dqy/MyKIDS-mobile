import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/settings_screen.dart';

class SettingsRepository extends FamilyRepository {
  final changes = <Map<String, dynamic>>[];
  var gate = Completer<void>();
  bool holdLogout = false;
  int logoutCalls = 0;
  SettingsRepository() {
    token = 'synthetic-settings-token';
    online = true;
    snapshot = {
      'user': {'id': 'parent', 'role': 'parent'},
      'family': {
        'timezone': 'Europe/Moscow',
        'quiet_start': '22:00',
        'quiet_end': '07:00',
        'day_start': '07:00',
        'day_end': '22:00',
      },
      'members': [
        {
          'id': 'grandma',
          'name': 'Бабушка',
          'role': 'relative',
          'active': 1,
          'create_tasks': 1,
          'view_tasks': 1,
          'review_tasks': 1,
          'permissions_revision': 'a' * 64,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    changes.add({
      'path': path,
      'method': method,
      'body': Map<String, dynamic>.from(body),
    });
    return {'ok': true};
  }

  @override
  Future<void> logout({bool remote = true}) async {
    logoutCalls++;
    generation++;
    if (holdLogout) await gate.future;
    token = null;
    snapshot = null;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsRepository repo;
  late BackgroundServices background;
  late List<String> platformCalls;
  late Future<void> Function() cancelNotifications;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  setUp(() {
    repo = SettingsRepository();
    background = BackgroundServices(repo);
    platformCalls = [];
    cancelNotifications = () async {};
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      if (call.method == 'cancelAll') await cancelNotifications();
      return true;
    });
    messenger.setMockMethodCallHandler(nativeCalls, (call) async {
      platformCalls.add(call.method);
      throw PlatformException(code: 'unavailable');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(nativeCalls, null);
    background.dispose();
    repo.client.close();
    repo.dispose();
  });

  Future<void> show(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsScreen(
            repository: repo,
            background: background,
            perform: (action) async {
              await action();
            },
            onUpdates: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'one relative switch sends only that permission and the displayed revision',
    (tester) async {
      await show(tester);
      await tap(tester, find.text('Бабушка'));
      await tap(tester, find.text('Смотреть свои задания'));
      expect(repo.changes.single, {
        'path': '/v1/members/grandma',
        'method': 'PATCH',
        'body': {'view_tasks': false, 'expected_revision': 'a' * 64},
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quiet hours do not overwrite day boundaries changed on another screen',
    (tester) async {
      await show(tester);
      await tap(tester, find.text('Часовой пояс и тихие часы'));
      (repo.snapshot!['family'] as Map)['day_start'] = '09:00';
      (repo.snapshot!['family'] as Map)['day_end'] = '20:00';
      await tap(tester, find.text('Сохранить'));
      final body = repo.changes.single['body'] as Map;
      expect(body['quiet_start'], '22:00');
      expect(body['quiet_end'], '07:00');
      expect(body.containsKey('day_start'), false);
      expect(body.containsKey('day_end'), false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('notification service failure cannot prevent account logout', (
    tester,
  ) async {
    cancelNotifications = () async {
      throw PlatformException(code: 'notification_service_down');
    };
    await show(tester);
    await tap(tester, find.text('Выйти и удалить данные с телефона'));
    expect(repo.signedIn, false);
    expect(repo.logoutCalls, 1);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('старые уведомления'), findsOneWidget);
  });

  testWidgets(
    'logout immediately starts and stays single while notification cleanup is stalled',
    (tester) async {
      final cleanup = Completer<void>();
      cancelNotifications = () => cleanup.future;
      repo.gate = Completer<void>();
      repo.holdLogout = true;
      await show(tester);
      final button = find.text('Выйти и удалить данные с телефона');
      await tester.scrollUntilVisible(
        button,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pump();
      expect(repo.logoutCalls, 1);
      final disabled = find.ancestor(
        of: find.text('Выходим…'),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(disabled).onPressed, isNull);
      repo.gate.complete();
      await tester.pump();
      await tester.pump();
      expect(repo.signedIn, false);
      // A bounded wait reports incomplete cleanup and does not keep the account open.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.textContaining('старые уведомления'), findsOneWidget);
      cleanup.complete();
      await tester.pumpAndSettle();
      expect(repo.logoutCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable Android settings give a usable explanation with large text',
    (tester) async {
      await show(tester, scale: 2);
      for (final label in [
        'Настройки уведомлений телефона',
        'Настройки работы в фоне',
        'Показ входящих звонков на экране',
      ]) {
        await tap(tester, find.text(label));
        expect(find.textContaining('Приложения → MyKIDS'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Dismiss this result before opening another settings screen.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
      }
      expect(platformCalls, [
        'notificationSettings',
        'batterySettings',
        'fullScreenSettings',
      ]);
    },
  );
}
