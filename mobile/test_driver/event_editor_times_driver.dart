import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^editor-(save-navigation|time-conflict|expanded-event|next-lesson|overlap-warning|keyboard-save)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected editor screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (captured.length != 6 ||
          result['synthetic_only'] != true ||
          result['outside_time_resolved'] != true ||
          result['overlap_blocked'] != true ||
          (result['native_keyboard_height_dp'] as num? ?? 0) <= 0) {
        throw StateError('Incomplete editor Android validation');
      }
      await File('../docs/editor-android-2026-10-13.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
