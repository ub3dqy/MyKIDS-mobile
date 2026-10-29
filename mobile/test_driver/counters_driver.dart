import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  const expected = {
    'counters-parent',
    'counters-child',
    'counters-money',
    'counters-chat',
  };
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!expected.contains(name) || bytes.isEmpty) {
        throw StateError('Unexpected counter screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (!captured.containsAll(expected) ||
          result['synthetic_only'] != true ||
          [
            'parent_review_updates',
            'child_daily_progress_updates',
            'requests_and_money_update',
            'pending_penalties_update',
            'quick_back_confirms_all_viewed_messages',
          ].any((key) => result[key] != true)) {
        throw StateError('Incomplete counter checks');
      }
      await File('../docs/counters-android-2026-10-15.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
