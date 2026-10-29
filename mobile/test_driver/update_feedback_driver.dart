import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (![
            'updates-no-update',
            'updates-check-error',
            'updates-check-new-version',
          ].contains(name) ||
          bytes.isEmpty) {
        return false;
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      for (final key in [
        'manual_joined_automatic_check',
        'no_update_message_visible',
        'settings_check_message_visible',
        'top_refresh_action_absent',
        'failure_not_misreported_as_no_updates',
        'new_version_prompt_visible_once',
      ]) {
        if (data?[key] != true) {
          throw StateError('Android feedback assertion failed: $key');
        }
      }
      await File('../docs/update-feedback-native-2026-10-11.json')
          .writeAsString(
            jsonEncode({
              for (final entry in data!.entries)
                if (entry.key != 'screenshots') entry.key: entry.value,
            }),
          );
    },
  );
}
