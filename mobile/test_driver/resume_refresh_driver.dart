import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final pictures = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!{'resume-papa', 'resume-mama', 'resume-kid'}.contains(name) ||
          bytes.isEmpty) {
        throw StateError('Unexpected resume screenshot');
      }
      await File('../docs/screenshots/$name.png').writeAsBytes(bytes);
      pictures.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final result = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      final cases = List<String>.from(result['cases'] as List? ?? []);
      final proofs = (result['proofs'] as List? ?? []).cast<Map>();
      if (pictures.length != 3 ||
          cases.length != 9 ||
          proofs.length != 6 ||
          result['independent_client_sessions'] != 3 ||
          result['clients_restarted'] != false ||
          result['same_flutter_state_during_each_return'] != true ||
          !proofs.every(
            (p) =>
                p['background_verified'] == true &&
                p['same_android_process'] == true &&
                (p['mode'] != 'lock' || p['screen_sleep_verified'] == true),
          )) {
        throw StateError('Incomplete Android lifecycle evidence');
      }
      await File('../docs/resume-android-2026-10-16.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    },
  );
}
