import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^task-rules-(required-type|penalty-field|optional-type|adult-confirmation|child-terms)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected task screenshot');
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
          result['adult_confirmed_once'] != true ||
          result['child_cannot_fine'] != true) {
        throw StateError('Incomplete Android task checks');
      }
      await File('../docs/task-rules-android-2026-10-13.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
