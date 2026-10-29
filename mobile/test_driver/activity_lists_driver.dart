import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(r'^activity-(today|today-filtered|history|penalty)$')
              .hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected activity screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (captured.length != 4 ||
          result['synthetic_only'] != true ||
          result['today_filters'] != true ||
          result['history_filters'] != true ||
          result['penalty_action_reachable'] != true) {
        throw StateError('Incomplete Android activity checks');
      }
      await File('../docs/activity-ui-android-2026-10-13.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
