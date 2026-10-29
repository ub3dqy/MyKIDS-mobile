import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final hashes = <String, String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(
            r'^child-v2-(today|calendar|tasks|money|family|submitted|reward|offline-saved)$',
          ).hasMatch(name) ||
          bytes.isEmpty) {
        return false;
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      hashes[name] = sha256.convert(bytes).toString();
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      for (final key in [
        'all_five_child_tabs_rendered',
        'all_visible_sprites_decoded',
        'submission_does_not_claim_coins',
        'confirmed_reward_visible',
        'animation_source_changes_native',
        'repeated_snapshot_does_not_repeat_celebration',
        'offline_submission_has_correct_feedback',
      ]) {
        if (data?[key] != true) throw StateError('Missing native proof: $key');
      }
      await File('../docs/child-visual-native-2026-10-13.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({...report, 'screenshot_sha256': hashes})}\n',
      );
    },
  );
}
