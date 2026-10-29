import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^fields-((child|parent|relative)-login-(top|bottom)|settings|settings-time-form|calendar|shared-form)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected field screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (result['roles_checked'] != 3 ||
          captured.length != 10 ||
          result['synthetic_only'] != true) {
        throw StateError('Incomplete Android field layout checks');
      }
      await File('../docs/fields-android-2026-10-12.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
