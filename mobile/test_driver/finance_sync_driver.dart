import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const expected = {
    'finance-sync-parent-payout',
    'finance-sync-parent-penalty',
    'finance-sync-child',
  };
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!expected.contains(name) || bytes.isEmpty) {
        throw StateError('Unexpected finance screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      final cases = List<String>.from(result['cases'] as List? ?? []);
      if (!captured.containsAll(expected) ||
          result['real_local_api'] != true ||
          result['independent_client_sessions'] != 3 ||
          result['clients_restarted'] != false ||
          result['lost_push_polling_recovered'] != true ||
          ![
            'confirm_reward',
            'child_cancel',
            'parent_reject',
            'grade_penalty',
            'task_penalty_negative_balance',
          ].every(cases.contains)) {
        throw StateError('Incomplete financial update checks');
      }
      await File('../docs/finance-sync-android-2026-10-16.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
