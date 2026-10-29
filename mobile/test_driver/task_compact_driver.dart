import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(r'^task-compact-(child|details|parent|active|review)$')
              .hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected task screenshot');
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
          result['details_optional'] != true ||
          result['timestamps_readable'] != true ||
          result['primary_actions_visible'] != true ||
          result['review_photos_zoomable'] != true) {
        throw StateError('Incomplete compact task checks');
      }
      await File('../docs/task-compact-android-2026-10-15.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
