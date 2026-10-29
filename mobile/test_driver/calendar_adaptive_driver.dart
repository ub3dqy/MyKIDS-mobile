import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(r'^adaptive-(empty-day|school-day|week|long-short-event)$')
              .hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected adaptive grid screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (captured.length != 4 ||
          result['all_hour_boundaries'] != 25 ||
          result['synthetic_only'] != true) {
        throw StateError('Incomplete adaptive calendar validation');
      }
      await File('../docs/adaptive-android-2026-10-12.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
