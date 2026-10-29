import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final device = Platform.environment['REAL_PUSH_DEVICE']!;
  if (!RegExp(r'^emulator-55(?:56|58|60)$').hasMatch(device)) {
    throw StateError('Only dedicated FCM emulators are allowed');
  }
  final result = await Process.run(r'E:\Android\Sdk\platform-tools\adb.exe', [
    '-P',
    '5038',
    '-s',
    device,
    'shell',
    'pm',
    'grant',
    'ru.mykids.mykids_family.parent',
    'android.permission.POST_NOTIFICATIONS',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Notification permission was not granted');
  }
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data?['real_fcm_received'] is! int ||
          data!['real_fcm_received'] < 1 ||
          data['fallback_polling'] != false ||
          data['checks'] is! List ||
          (data['checks'] as List).length != 10) {
        throw StateError('Real FCM receipt and refresh were not proven');
      }
      await File('../docs/real-push-${data['actor']}-2026-10-17.json')
          .writeAsString(jsonEncode(data));
    },
  );
}
