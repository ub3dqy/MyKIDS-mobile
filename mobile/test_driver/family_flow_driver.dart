import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (name != 'child-home' || bytes.isEmpty) return false;
      await File('../docs/screenshots/audit-fixes-offline-child-home.png')
          .writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      for (final key in [
        'synthetic_only',
        'offline_result_survives_restart',
        'one_submission_after_repeated_sync',
        'no_reward_before_approval',
        'logout_removes_private_routes_and_cache',
      ]) {
        if (report[key] != true) {
          throw StateError('Missing offline proof: $key');
        }
      }
      await File('../docs/audit-fixes-offline-native-2026-10-13.json')
          .writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(report)}\n',
          );
    },
  );
}
