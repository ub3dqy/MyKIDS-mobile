import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const expected = {
    'grade-sync-pending-penalty',
    'grade-sync-child-coins',
    'grade-sync-history',
  };
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!expected.contains(name) || bytes.isEmpty) {
        throw StateError('Unexpected grade screenshot');
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
          result['independent_client_sessions'] != 3 ||
          result['real_local_api'] != true ||
          result['synthetic_only'] != true ||
          result['clients_restarted'] != false ||
          result['lost_push_polling_recovered'] != true ||
          result['notes_do_not_reapply_rules'] != true ||
          result['no_double_reward'] != true ||
          ![
            'add_calendar_grade',
            'raise_grade',
            'note_only_no_new_reward',
            'lower_grade_pending_penalty',
            'confirmed_penalty',
            'correct_after_penalty',
            'same_grade_no_double_reward',
            'zero_reward_history_grade',
            'history_date_change',
          ].every(cases.contains)) {
        throw StateError('Incomplete grade update checks');
      }
      await File('../docs/grade-sync-android-2026-10-16.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
