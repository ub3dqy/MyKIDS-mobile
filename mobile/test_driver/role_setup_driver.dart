import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(
            r'^unified-(role-choice|(child|parent|relative)-(login|contacts))$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected unified app screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (report['synthetic_only'] != true ||
          report['roles_checked'] != 3 ||
          captured.length != 7) {
        throw StateError('Incomplete unified app checks');
      }
      await File('../docs/unified-android-2026-10-12.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
  );
}
