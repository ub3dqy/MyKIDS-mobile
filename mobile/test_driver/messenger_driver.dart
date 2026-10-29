import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final result = await Process.run(r'E:\Android\Sdk\platform-tools\adb.exe', [
    '-s',
    'emulator-5554',
    'shell',
    'pm',
    'grant',
    'ru.mykids.mykids_family.parent',
    'android.permission.RECORD_AUDIO',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Owned emulator permission setup failed');
  }
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(
            r'^messenger-((child|parent|relative)-(chats|calls|conversation|recording)|incoming-(audio|video))$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        return false;
      }
      final filename = name.startsWith('messenger-incoming-')
          ? 'incoming-${name.endsWith('audio') ? 'audio' : 'video'}-invitation-messenger'
          : name;
      await File('../docs/screenshots/$filename.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (report['synthetic_only'] != true ||
          report['native_recording_nonempty'] != true) {
        throw StateError('Incomplete messenger checks');
      }
      await File('../docs/messenger-android-2026-10-12.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
  );
}
