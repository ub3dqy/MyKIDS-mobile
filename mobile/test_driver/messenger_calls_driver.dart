import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  for (final permission in ['RECORD_AUDIO', 'CAMERA']) {
    final result = await Process.run(r'E:\Android\Sdk\platform-tools\adb.exe', [
      '-s',
      'emulator-5554',
      'shell',
      'pm',
      'grant',
      'ru.mykids.mykids_family.parent',
      'android.permission.$permission',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Owned emulator call permission setup failed');
    }
  }
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^(today-compact-coins|incoming-(audio|video)-connected)$')
              .hasMatch(name) ||
          bytes.isEmpty) {
        return false;
      }
      await File('../docs/screenshots/$name-messenger.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (report['automatic_device_registration'] != true ||
          (report['cases'] as List).length != 2) {
        throw StateError('Incomplete native media evidence');
      }
      await File('../docs/messenger-calls-android-2026-10-12.json')
          .writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(report)}\n',
          );
    },
  );
}
