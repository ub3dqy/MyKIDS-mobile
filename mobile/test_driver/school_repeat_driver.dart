import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^school-repeat-(school-subjects|daily-form|save-visible|today|stop-confirmation)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (captured.length != 5 ||
          result['synthetic_only'] != true ||
          result['school_container_has_no_grade'] != true ||
          result['stop_requires_confirmation'] != true ||
          result['all_seven_days_saved'] != true ||
          result['separate_daily_instances'] != true) {
        throw StateError('Incomplete Android checks');
      }
      await File('../docs/school-repeat-android-2026-10-13.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
