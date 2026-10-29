import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const expected = {
    'calendar-sync-task-updated',
    'calendar-sync-event-replaced',
    'calendar-sync-event-cancelled',
    'calendar-sync-details-updated',
    'calendar-sync-details-cancelled',
  };
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!expected.contains(name) || bytes.isEmpty) {
        throw StateError('Unexpected calendar screenshot');
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
          result['synthetic_only'] != true ||
          result['independent_client_sessions'] != 3 ||
          result['clients_restarted'] != false ||
          result['lost_push_polling_recovered'] != true ||
          result['no_money_changes'] != true ||
          ![
            'create_task',
            'edit_task',
            'plan_task',
            'reschedule_task',
            'remove_task_plan',
            'cancel_task',
            'create_event',
            'edit_event',
            'replace_event_day',
            'cancel_event_day',
            'restore_event_day',
            'archive_event',
            'create_repeating_task',
            'edit_future_tasks',
            'stop_repeating_task',
            'lost_signal_polling',
            'open_event_details_update_all_clients',
            'open_event_details_cancel_all_clients',
          ].every(cases.contains)) {
        throw StateError('Incomplete calendar update checks');
      }
      await File('../docs/calendar-sync-android-2026-10-16.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
