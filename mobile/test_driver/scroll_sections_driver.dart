import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!['scroll-coins-child', 'scroll-coins-parent'].contains(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected scroll screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      if (captured.length != 2 ||
          result['synthetic_only'] != true ||
          result['child']?['oldest_reached'] != true ||
          result['parent']?['oldest_reached'] != true) {
        throw StateError('Incomplete scroll checks');
      }
      await File('../docs/scroll-sections-android-2026-10-15.json')
          .writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(result)}\n',
          );
    },
  );
}
