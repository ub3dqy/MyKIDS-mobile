import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/call_permissions.dart';
import 'package:mykids_family/repository.dart';

void main() {
  testWidgets(
    'copied call report uses fresh native permissions and incoming transport facts',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final report = <String, dynamic>{
        'notifications': true,
        'fullScreen': true,
        'microphone': true,
        'camera': true,
        'callAlerts': false,
        'lockScreen': false,
        'nativeAccountReady': true,
        'lastIncomingPush': {
          'priority': 1,
          'originalPriority': 1,
          'deviceLocked': true,
        },
        'incomingOutcome': 'notification_posted',
      };
      String? clipboard;
      messenger.setMockMethodCallHandler(nativeCalls, (_) async => report);
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (_) async => true,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      final repo = FamilyRepository();
      final background = BackgroundServices(repo)
        ..callsNotificationsReady = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CallPermissionNotice(
                background: background,
                details: true,
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Скопировать отчёт о звонках'));
      await tester.tap(find.text('Скопировать отчёт о звонках'));
      await tester.pumpAndSettle();
      expect(jsonDecode(clipboard!), report);
      expect(background.callsNotificationsReady, isTrue);
      expect(background.callsAlertsReady, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      background.dispose();
      repo.client.close();
      repo.dispose();
      messenger.setMockMethodCallHandler(nativeCalls, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );

  testWidgets(
    'a disabled call screen is explained and opens its permission; resume removes the warning',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var fullScreen = false;
      final opened = <String>[];
      messenger.setMockMethodCallHandler(nativeCalls, (call) async {
        if (call.method == 'permissions') {
          return {
            'notifications': true,
            'fullScreen': fullScreen,
            'callAlerts': true,
            'lockScreen': true,
            'microphone': true,
            'camera': true,
            'phone': 'Samsung test',
            'android': '16',
          };
        }
        opened.add(call.method);
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (_) async => true,
      );
      final repo = FamilyRepository();
      final background = BackgroundServices(repo);
      await background.checkCallPermissions();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CallPermissionNotice(background: background)),
        ),
      );
      expect(
        find.textContaining('экран звонка поверх блокировки не разрешён'),
        findsOneWidget,
      );
      await tester.tap(find.text('Настроить звонки'));
      await tester.pumpAndSettle();
      expect(opened, contains('fullScreenSettings'));
      fullScreen = true;
      await background.checkCallPermissions();
      await tester.pumpAndSettle();
      expect(find.text('Настроить звонки'), findsNothing);
      expect(background.callsNeedSetup, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      background.dispose();
      repo.client.close();
      repo.dispose();
      messenger.setMockMethodCallHandler(nativeCalls, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        null,
      );
    },
  );

  testWidgets(
    'changes in microphone and camera grants notify the settings card',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var granted = false;
      messenger.setMockMethodCallHandler(
        nativeCalls,
        (_) async => {
          'notifications': true,
          'fullScreen': true,
          'callAlerts': true,
          'lockScreen': true,
          'microphone': granted,
          'camera': granted,
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (_) async => true,
      );
      final repo = FamilyRepository();
      final background = BackgroundServices(repo);
      await background.checkCallPermissions();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallPermissionNotice(background: background, details: true),
          ),
        ),
      );
      expect(
        find.textContaining('Разрешите микрофон один раз'),
        findsOneWidget,
      );
      expect(find.text('Разрешить камеру для звонков'), findsOneWidget);
      granted = true;
      await background.checkCallPermissions();
      await tester.pumpAndSettle();
      expect(find.text('Разрешить камеру для звонков'), findsNothing);
      expect(background.callsNeedSetup, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      background.dispose();
      repo.client.close();
      repo.dispose();
      messenger.setMockMethodCallHandler(nativeCalls, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        null,
      );
    },
  );
}
