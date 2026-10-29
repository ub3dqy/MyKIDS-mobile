import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^task-result-(rules-upper|rules-lower|review-25|verified-25|two-pages|supplement-one|supplement-two)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected task result screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (captured.length != 7 ||
          result['synthetic_only'] != true ||
          result['native_gallery_selection'] != true ||
          result['selected_together'] != 2 ||
          result['supplemented_photos'] != 1 ||
          result['reward_preview'] != 25) {
        throw StateError('Incomplete task rewards and photos checks');
      }
      await File('../docs/task-results-android-2026-10-14.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
