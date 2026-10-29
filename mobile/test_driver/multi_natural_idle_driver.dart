import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final device = Platform.environment['REAL_PUSH_DEVICE']!;
  if (!RegExp(r'^emulator-55(?:56|58|60)$').hasMatch(device)) {
    throw StateError('Only dedicated quiet calendar emulators are allowed');
  }
  final permission = await Process.run(
    r'E:\Android\Sdk\platform-tools\adb.exe',
    [
      '-P',
      '5038',
      '-s',
      device,
      'shell',
      'pm',
      'grant',
      'ru.mykids.mykids_family.parent',
      'android.permission.POST_NOTIFICATIONS',
    ],
  );
  if (permission.exitCode != 0) {
    throw StateError('Notification permission failed');
  }
  await integrationDriver(
    timeout: const Duration(minutes: 6),
    responseDataCallback: (data) async {
      if (data?['bootstrap'] != true ||
          data?['api_transport'] != 'guest_network_no_adb_reverse' ||
          !['kid', 'papa', 'mama'].contains(data?['actor'])) {
        throw StateError('Bootstrap did not finish');
      }
      await File(
        '../docs/multi-natural-idle-fixed-bootstrap-${data!['actor']}-2026-10-19.json',
      ).writeAsString(jsonEncode(data));
    },
  );
}
