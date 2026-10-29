import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const expected = {
    'cross-device-parent',
    'cross-device-child',
    'cross-device-coins',
  };
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!expected.contains(name) || bytes.isEmpty) {
        throw StateError('Unexpected screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (!captured.containsAll(expected) ||
          result['real_local_api'] != true ||
          result['independent_client_sessions'] != 3 ||
          result['clients_restarted'] != false ||
          result['lost_push_polling_recovered'] != true ||
          (result['cases'] as List?)?.length != 3) {
        throw StateError('Incomplete three-client checks');
      }
      await File('../docs/cross-device-android-2026-10-16.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
