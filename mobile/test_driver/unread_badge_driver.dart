import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (![
            'unread-parent-before',
            'unread-parent-after',
            'unread-parent-new',
            'unread-child-after',
          ].contains(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected unread screenshot');
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
          ['parent', 'child'].any(
            (role) =>
                result[role]?['badge_cleared_on_return'] != true ||
                result[role]?['new_messages_stay_unread'] != true,
          )) {
        throw StateError('Incomplete unread badge checks');
      }
      await File('../docs/unread-badge-android-2026-10-15.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
