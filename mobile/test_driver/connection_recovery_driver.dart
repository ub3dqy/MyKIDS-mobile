import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final screenshots = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!{
            'reconnect-papa-money',
            'reconnect-mama-money',
            'reconnect-kid-money',
          }.contains(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected recovery screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      screenshots.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      final cases = List<String>.from(result['cases'] as List? ?? []);
      if (result['real_local_api'] != true ||
          result['independent_client_sessions'] != 3 ||
          result['clients_restarted'] != false ||
          result['idempotent_money_retry_verified'] != true ||
          screenshots.length != 3 ||
          cases.length != 21) {
        throw StateError('Incomplete recovery evidence');
      }
      await File('../docs/reconnect-android-2026-10-16.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
