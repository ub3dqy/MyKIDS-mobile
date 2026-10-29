import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^photo-viewer-(selected-fit|selected-pinch|selected-second|review-zoom|review-fit)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected photo viewer screenshot');
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
          result['selected_pages'] != 2 ||
          result['pinch_zoom'] != true ||
          result['double_tap_zoom'] != true ||
          result['pan'] != true ||
          result['parent_review'] != true ||
          result['session_close'] != true) {
        throw StateError('Incomplete photo viewer checks');
      }
      await File('../docs/task-photo-viewer-android-2026-10-14.json')
          .writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(result)}\n',
          );
    },
  );
}
