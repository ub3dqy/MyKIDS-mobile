import 'dart:convert';
import 'dart:io';

import 'package:mykids_family/push_registration.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'real_push_sync_test.dart' show stateOf;

const bridge = 'http://10.0.2.2:19079';

// Only observes the actual callback. Opening another SQLite connection here
// would contend with the real background worker. The host verifies persisted
// data separately through passive SQLite/WAL copies, without any app-side sync.
@pragma('vm:entry-point')
Future<void> observeHandoverPush(RemoteMessage message) async {
  final result = <String, dynamic>{
    'message_id': message.messageId,
    'kind': message.data['kind'],
    'pid': pid,
  };
  try {
    await incomingPush(message);
    result['production_handler_ok'] = true;
  } catch (error) {
    result['error'] = error.runtimeType.toString();
  } finally {
    final support = await getApplicationSupportDirectory();
    final folder = await Directory('${support.path}/cold-push-receipts')
        .create(recursive: true);
    final receipt = sha256.convert(
      utf8.encode(message.messageId ?? 'missing-id'),
    );
    // Cold-start callbacks may run concurrently in separate background engines.
    // Separate files prevent append handles from overwriting one another.
    await File('${folder.path}/$receipt.json')
        .writeAsString('${jsonEncode(result)}\n', flush: true);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('persist real FCM registration for actual network handover', (
    tester,
  ) async {
    final repo = FamilyRepository();
    final services = BackgroundServices(repo);
    var key = const String.fromEnvironment('COLD_PUSH_RUN');
    Future<Map<String, dynamic>> call(
      String path,
      Map<String, dynamic> body,
    ) async {
      final response = await http
          .post(
            Uri.parse('$bridge/__probe/$path'),
            headers: {'Content-Type': 'application/json', 'X-Cold-Push': key},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      expect(response.statusCode, 200);
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }

    try {
      foundation.debugPrint('BOOTSTRAP initialize Firebase');
      await Firebase.initializeApp().timeout(const Duration(seconds: 30));
      foundation.debugPrint('BOOTSTRAP Firebase ready');
      expect(Firebase.app().options.projectId, 'mykids-family-ec459');
      String? token;
      for (var attempt = 0; attempt < 3 && token == null; attempt++) {
        try {
          // Verify the same token-registration path as the production app.
          // ignore: deprecated_member_use
          token = await requestFamilyPushTarget().timeout(
            const Duration(seconds: 75),
          );
        } catch (_) {
          if (attempt == 2) rethrow;
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      }
      foundation.debugPrint('BOOTSTRAP Google token ready');
      final setup = await call('register', {'device_token': token});
      key = setup['client_key'] as String;
      final actor = setup['actor'] as String;
      foundation.debugPrint('BOOTSTRAP synthetic role assigned');
      await repo.initialize(actor == 'kid' ? 'child' : 'parent');
      foundation.debugPrint('BOOTSTRAP storage ready');
      await repo.login(bridge, actor, 'synthetic-cold-push-12345');
      foundation.debugPrint('BOOTSTRAP login ready');
      FirebaseMessaging.onBackgroundMessage(observeHandoverPush);
      await services.initialize((_) async {});
      if (const bool.fromEnvironment('WEAK_PUSH_RESET_FIXTURE')) {
        // Reset only retry jobs from an earlier isolated test attempt.
        await Workmanager().cancelByUniqueName('mykids-push-retry');
      }
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!services.pushReady && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(services.pushReady, isTrue);
      await repo.sync();
      await tester.pumpAndSettle();
      await call('ready', {'pid': pid, 'state': stateOf(repo)});
      binding.reportData = {
        'actor': actor,
        'pid': pid,
        'bootstrap': true,
        'api_transport': 'guest_network_no_adb_reverse',
      };
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      services.dispose();
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
