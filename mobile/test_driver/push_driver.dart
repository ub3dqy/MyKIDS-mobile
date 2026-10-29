import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final permission = await Process.run(
    r'E:\Android\Sdk\platform-tools\adb.exe',
    [
      '-s',
      'emulator-5554',
      'shell',
      'pm',
      'grant',
      'ru.mykids.mykids_family.parent',
      'android.permission.POST_NOTIFICATIONS',
    ],
  );
  if (permission.exitCode != 0) {
    throw StateError('Could not grant permission on the test emulator');
  }
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data?['fcm_received'] != true) {
        throw StateError(
          'Actual Android notification receipt was not verified',
        );
      }
      await File('../docs/fcm-delivery-2026-10-11.json').writeAsString(
        jsonEncode({
          'fcm_received': true,
          'project': data?['project'],
          'scope':
              'Android emulator, foreground; closed-app delivery not verified',
        }),
      );
    },
  );
}
