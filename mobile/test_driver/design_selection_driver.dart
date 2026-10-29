import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data == null ||
          data['all_five_selected_in_real_settings'] != true ||
          data['stored_by_android_secure_storage'] != true ||
          data['family_example_unchanged'] != true) {
        throw StateError('Incomplete native appearance acceptance');
      }
      final directory = Directory('../docs/designs-main-2026-10-20/native');
      await directory.create(recursive: true);
      final images = (data['captures'] as Map).cast<String, String>();
      if (images.length != 35) throw StateError('Missing native screens');
      for (final entry in images.entries) {
        if (!RegExp(
          r'^(blocks|squad|comic|workshop|islands)-(picker|settings|today|calendar-day|tasks|money|chats)$',
        ).hasMatch(entry.key)) {
          throw StateError('Unexpected capture name');
        }
        await File('${directory.path}/${entry.key}.png')
            .writeAsBytes(base64Decode(entry.value));
      }
      final report = Map<String, dynamic>.from(data)..remove('captures');
      report['native_screens'] = images.keys.toList();
      await File(
        '../docs/designs-main-2026-10-20/evidence/native-acceptance.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    },
  );
}
