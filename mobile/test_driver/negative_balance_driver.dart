import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^negative-balance-(full-fine|confirmation|child-debt|review-today|review-result)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected negative balance screenshot');
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
          result['negative_child_balance_visible'] != true ||
          result['full_fine_confirmation'] != true ||
          result['new_exchange_disabled'] != true ||
          result['specific_evening_result_opened'] != true ||
          result['navigation_did_not_approve'] != true) {
        throw StateError('Incomplete Android balance checks');
      }
      await File('../docs/negative-balance-android-2026-10-13.json')
          .writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(result)}\n',
          );
    },
  );
}
