import 'dart:convert';

import 'package:mykids_family/push_registration.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';

// Only the private owned emulator harness receives the test registration token.
// No family server, account or conversation is used by this setup.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'prepare owned Android emulator for locked incoming push checks',
    (tester) async {
      await Firebase.initializeApp();
      expect(Firebase.app().options.projectId, 'mykids-family-ec459');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Проверка входящих звонков')),
        ),
      );
      await FirebaseMessaging.instance.requestPermission();
      await nativeCalls.invokeMethod('identity', {
        'user': '00000000000000000000000000000001',
        'session': List.filled(64, 'a').join(),
      });
      final token = await requestFamilyPushTarget().timeout(
        const Duration(seconds: 40),
      );
      expect(token, isNotNull);
      final generic = FirebaseMessaging.onMessage
          .firstWhere((message) => message.data['kind'] == 'check')
          .timeout(const Duration(seconds: 40));
      final response = await http
          .post(
            Uri.parse('http://127.0.0.1:8879/setup'),
            headers: {
              'Content-Type': 'application/json',
              'X-MyKIDS-Emulator-Test': 'locked-calls',
            },
            body: jsonEncode({'device_token': token}),
          )
          .timeout(const Duration(seconds: 15));
      expect(response.statusCode, 200);
      expect((await generic).data['kind'], 'check');
      final report = await nativeCalls.invokeMapMethod<String, dynamic>(
        'callDiagnostics',
      );
      expect(report!['nativeAccountReady'], isTrue);
      binding.reportData = {
        'synthetic_only': true,
        'native_account_ready': true,
        'generic_push_preserved': true,
      };
    },
  );
}
