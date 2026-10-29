import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final hashes = <String, String>{};
  await Directory('../docs/screenshots').create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^calendar-(morning-school|morning-extra|morning-task|day|week|month)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        return false;
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      hashes[name] = sha256.convert(bytes).toString();
      return true;
    },
    responseDataCallback: (data) async {
      if (hashes.length != 6) {
        throw StateError('Expected all six calendar screenshots');
      }
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      for (final key in [
        'synthetic_only',
        'all_three_periods_rendered',
        'authored_frames_change',
        'school_subjects_grouped',
        'morning_once_daily',
        'next_day_overview',
        'native_reminders_registered',
        'reminder_cancellation_verified',
      ]) {
        if (report[key] != true) {
          throw StateError('Missing native calendar evidence: $key');
        }
      }
      await File('../docs/calendar-native-2026-10-13.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({...report, 'screenshot_sha256': hashes})}\n',
      );
    },
  );
}
