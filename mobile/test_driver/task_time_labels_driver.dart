import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(r'^task-time-(morning|evening)$').hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected task time screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (captured.length != 2 ||
          result['synthetic_only'] != true ||
          result['same_title_and_deadline'] != true ||
          result['calendar_times_visible_collapsed'] != true) {
        throw StateError('Incomplete Android task time checks');
      }
      await File('../docs/task-time-android-2026-10-13.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
