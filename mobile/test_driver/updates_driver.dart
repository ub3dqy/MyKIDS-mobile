import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const adb = r'E:\Android\Sdk\platform-tools\adb.exe';
  final driver = await FlutterDriver.connect();
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (true) {
    final ready = await Process.run(adb, [
      '-s',
      'emulator-5554',
      'shell',
      'test',
      '-f',
      '/sdcard/Android/data/ru.mykids.mykids_family.parent/files/mykids-updates/native-ready',
    ]);
    if (ready.exitCode == 0) break;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Native updater did not create its test directory');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  for (final command in [
    [
      'shell',
      'mkdir',
      '-p',
      '/sdcard/Android/data/ru.mykids.mykids_family.parent/files/mykids-updates',
    ],
    [
      'shell',
      'cp',
      '/data/local/tmp/mykids-unified-updater-fixture-0.1.11.apk',
      '/sdcard/Android/data/ru.mykids.mykids_family.parent/files/mykids-updates/MyKIDS-0.1.11.apk',
    ],
    [
      'shell',
      'cp',
      '/data/local/tmp/mykids-unified-wrong-signer.apk',
      '/sdcard/Android/data/ru.mykids.mykids_family.parent/files/mykids-updates/MyKIDS-0.1.10.apk',
    ],
    [
      'shell',
      'cp',
      '/data/local/tmp/mykids-unified-foreign-package.apk',
      '/sdcard/Android/data/ru.mykids.mykids_family.parent/files/mykids-updates/MyKIDS-0.1.9.apk',
    ],
  ]) {
    final result = await Process.run(adb, ['-s', 'emulator-5554', ...command]);
    if (result.exitCode != 0) {
      throw StateError('The isolated native APK fixture could not be copied');
    }
  }
  await integrationDriver(
    driver: driver,
    onScreenshot: (name, bytes, [arguments]) async {
      if (name != 'unified-update-login' || bytes.isEmpty) return false;
      await File('../docs/screenshots/unified-update-login.png')
          .writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      if (data?['native_signature_verified'] != true ||
          data?['invalid_candidates_rejected'] != true) {
        throw StateError('Native update validation did not pass');
      }
      await File(
        '../docs/unified-updates-native-2026-10-12.json',
      ).writeAsString(
        jsonEncode({
          'native_signature_verified': data!['native_signature_verified'],
          'invalid_candidates_rejected': data['invalid_candidates_rejected'],
          'foreign_package_rejected': data['foreign_package_rejected'],
          'foreign_signer_rejected': data['foreign_signer_rejected'],
          'scope': data['scope'],
        }),
      );
    },
  );
}
