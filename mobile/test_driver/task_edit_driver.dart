import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^task-edit-(reviewer-choices|prefilled-title|zero-reward|save-visible|edited-task)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected task edit screenshot');
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
          result['both_parents_choice'] != true ||
          result['zero_reward_saved'] != true ||
          result['same_task_edited'] != true ||
          result['displayed_version_submitted'] != true) {
        throw StateError('Incomplete Android task edit checks');
      }
      await File('../docs/task-edit-android-2026-10-13.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
