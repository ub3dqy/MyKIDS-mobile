import 'dart:io';
import 'dart:convert';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(
            r'^contacts-((papa|stepa|grandma1)-(list|private-chat)|shared-chat|four-person-call-component)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected contacts screenshot');
      }
      final file = File('../docs/screenshots/$name.png');
      await file.writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (report['synthetic_only'] != true || report['roles_checked'] != 3) {
        throw StateError('Incomplete Android contacts checks');
      }
      await File('../docs/contacts-android-2026-10-12.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
  );
}
