import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const folder =
      '/sdcard/Android/data/ru.mykids.mykids_family.parent/files/mykids-updates';
  Future<ProcessResult> adb(List<String> args) => Process.run(
    r'E:\Android\Sdk\platform-tools\adb.exe',
    ['-s', 'emulator-5554', ...args],
  );
  Future<void> command(List<String> args) async {
    final result = await adb(args);
    if (result.exitCode != 0) {
      throw StateError('Emulator command failed: ${result.stderr}');
    }
  }

  var finished = false;
  await command(['shell', 'rm', '-f', '$folder/host-checkpoint.request']);
  Object? hostFailure;
  final handled = <String>{};
  // Android screenshots are delivered only after tests finish. Coordinate live
  // actions through files in this isolated test application's folder.
  unawaited(() async {
    try {
      while (!finished) {
        final request = await adb([
          'shell',
          'cat',
          '$folder/host-checkpoint.request',
        ]);
        final name = request.stdout.toString().trim();
        if (request.exitCode == 0 && !handled.contains(name)) {
          switch (name) {
            case 'prepare-download':
              await command(['emu', 'network', 'speed', 'full']);
            case 'lock-download':
              await command(['shell', 'input', 'keyevent', '223']);
              await Future<void>.delayed(const Duration(seconds: 10));
              await command(['shell', 'input', 'keyevent', '224']);
              await command(['shell', 'wm', 'dismiss-keyguard']);
            case 'finish-download':
              await command(['emu', 'network', 'speed', 'full']);
            default:
              throw StateError('Unexpected checkpoint: $name');
          }
          await command(['shell', 'touch', '$folder/checkpoint-$name.done']);
          handled.add(name);
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } catch (error) {
      hostFailure = error;
      stderr.writeln('Host checkpoint failed: $error');
    }
  }());
  await integrationDriver(
    responseDataCallback: (data) async {
      finished = true;
      if (hostFailure != null) {
        throw StateError('Host action failed: $hostFailure');
      }
      final report = Map<String, dynamic>.from(data ?? {});
      final phase = report['phase'];
      if (phase != 'start' && phase != 'resume') {
        throw StateError('Missing persistence evidence');
      }
      await File('../docs/download-persistence-$phase-2026-10-12.json')
          .writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(report)}\n',
          );
    },
  );
}
