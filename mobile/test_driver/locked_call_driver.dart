import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  const adb = r'E:\Android\Sdk\platform-tools\adb.exe';
  final owned = await Process.run(adb, [
    '-s',
    'emulator-5554',
    'shell',
    'getprop',
    'ro.boot.qemu',
  ]);
  final avd = await Process.run(adb, [
    '-s',
    'emulator-5554',
    'emu',
    'avd',
    'name',
  ]);
  if (owned.exitCode != 0 ||
      owned.stdout.toString().trim() != '1' ||
      !avd.stdout.toString().contains('MyKIDS_Family_API36')) {
    throw StateError('Only the owned MyKIDS emulator may be used');
  }
  final permission = await Process.run(adb, [
    '-s',
    'emulator-5554',
    'shell',
    'pm',
    'grant',
    'ru.mykids.mykids_family.parent',
    'android.permission.POST_NOTIFICATIONS',
  ]);
  if (permission.exitCode != 0) {
    throw StateError('Notification permission setup failed');
  }
  final bridge = await Process.run(adb, [
    '-s',
    'emulator-5554',
    'reverse',
    'tcp:8879',
    'tcp:8879',
  ]);
  if (bridge.exitCode != 0) {
    throw StateError('Owned emulator bridge setup failed');
  }
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data?['synthetic_only'] != true ||
          data?['native_account_ready'] != true ||
          data?['generic_push_preserved'] != true) {
        throw StateError('Owned emulator push setup did not finish');
      }
    },
  );
}
