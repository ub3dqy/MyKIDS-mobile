import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const expected = {
    'reward-sync-child-price-goal',
    'reward-sync-parent-delete-confirmation',
    'reward-sync-deleted-with-existing-request',
  };
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!expected.contains(name) || bytes.isEmpty) {
        throw StateError('Unexpected reward screenshot');
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
          result['request_price_preserved'] != true ||
          result['lost_push_polling_recovered'] != true ||
          ![
            'create_reward',
            'choose_goal',
            'increase_price_and_goal_progress',
            'edit_description',
            'hide_reward',
            'restore_reward',
            'decrease_price_and_request_button',
            'request_keeps_displayed_price',
            'open_confirmation_updates',
            'delete_keeps_request_and_balance',
            'fulfil_deleted_reward_at_agreed_price',
            'external_delete_disables_confirmation',
            'lost_signal_polling',
            'delete_by_other_parent',
          ].every(cases.contains)) {
        throw StateError('Incomplete reward synchronization checks');
      }
      await File('../docs/reward-sync-android-2026-10-16.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
