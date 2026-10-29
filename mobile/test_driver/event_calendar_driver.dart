import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^calendar-((parent|child|relative)-(day|details)|week|month|editor-(top|lessons)-large)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected calendar screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (captured.length != 10 ||
          result['roles_checked'] != 3 ||
          result['synthetic_only'] != true) {
        throw StateError('Incomplete calendar checks');
      }
      await File('../docs/calendar-android-2026-10-12.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
