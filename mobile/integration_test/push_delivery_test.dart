import 'dart:convert';

import 'package:mykids_family/push_registration.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:uuid/uuid.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('FCM arrives from the family server on real Android', (
    tester,
  ) async {
    final repo = FamilyRepository();
    await repo.initialize('child');
    await repo.login('http://10.0.2.2:8765', 'testkid', 'emulator-only-12345');
    await tester.pumpWidget(MyKidsApp(repository: repo));
    await tester.pumpAndSettle();
    await Firebase.initializeApp();
    expect(Firebase.app().options.projectId, 'mykids-family-ec459');
    await FirebaseMessaging.instance.requestPermission();
    final token = await requestFamilyPushTarget().timeout(
      const Duration(seconds: 35),
    );
    expect(token, isNotNull);
    final nonce = const Uuid().v4().replaceAll('-', '');
    final received = FirebaseMessaging.onMessage
        .firstWhere((message) => message.data['entity_id'] == nonce)
        .timeout(const Duration(seconds: 45));
    final sent = await http
        .post(
          Uri.parse('http://10.0.2.2:8766/push-check'),
          headers: {
            'Content-Type': 'application/json',
            'X-MyKIDS-Emulator-Test': 'family-check-2026',
          },
          body: jsonEncode({'device_token': token, 'nonce': nonce}),
        )
        .timeout(const Duration(seconds: 50));
    expect(sent.statusCode, 200);
    expect((await received).data['kind'], 'check');
    binding.reportData = {
      'fcm_received': true,
      'project': 'mykids-family-ec459',
    };
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await repo.logout();
    await repo.db!.close();
    repo.client.close();
    repo.dispose();
  });
}
