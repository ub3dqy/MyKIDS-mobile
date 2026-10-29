import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final quietOnly = Platform.environment['BACKGROUND_PUSH_CASE'] == 'quiet';
  final expected = quietOnly ? 10 : 30;
  final prefix = quietOnly ? 'background-push-quiet' : 'background-push';
  final day = quietOnly ? '2026-10-18' : '2026-10-17';
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
    timeout: const Duration(minutes: 30),
    responseDataCallback: (data) async {
      if (data?['real_background_delivery'] != true ||
          data?['checks'] is! List ||
          (data!['checks'] as List).length != expected) {
        throw StateError('All background and locked phases must pass');
      }
      await File('../docs/$prefix-${data['actor']}-$day.json')
          .writeAsString(jsonEncode(data));
    },
  );
}
