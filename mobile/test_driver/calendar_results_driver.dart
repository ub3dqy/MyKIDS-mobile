import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^results-(parent-events|grade-form|next-date|child-review|relative-completed)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected calendar result screenshot');
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
          result['child_submitted'] != true ||
          result['relative_confirmed'] != true) {
        throw StateError('Incomplete Android calendar results verification');
      }
      await File('../docs/results-android-2026-10-13.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
