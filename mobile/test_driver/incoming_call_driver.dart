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
      throw StateError('Test emulator permission setup failed');
    }
  }
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (![
            'today-compact-coins',
            'incoming-audio-connected',
            'incoming-video-connected',
          ].contains(name) ||
          bytes.isEmpty) {
        return false;
      }
      await File('../docs/screenshots/$name-0.1.8.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (report['automatic_device_registration'] != true ||
          (report['cases'] as List).length != 2) {
        throw StateError('Incomplete call evidence');
      }
      await File('../docs/calls-android-2026-10-12.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
  );
}
