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
      'android.permission.CAMERA',
    ],
  );
  if (permission.exitCode != 0) {
    throw StateError('Cannot grant camera permission to the isolated test app');
  }
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!['parent-invitation-qr', 'child-invitation-filled'].contains(name) ||
          bytes.isEmpty) {
        return false;
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      if (data?['camera_started_on_emulator'] != true ||
          data?['wrong_role_rejected'] != true ||
          data?['invite_field_filled'] != true ||
          data?['registration_not_submitted'] != true ||
          (data?['qr_roles_decoded'] as List?)?.length != 3) {
        throw StateError('Android QR invitation verification failed');
      }
      await File('../docs/invitations-native-2026-10-13.json').writeAsString(
        jsonEncode({
          for (final entry in data!.entries)
            if (entry.key != 'screenshots') entry.key: entry.value,
        }),
      );
    },
  );
}
