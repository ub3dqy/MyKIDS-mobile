import 'dart:convert';
import 'dart:io';

import 'package:mykids_family/push_registration.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/repository.dart';
import 'package:path_provider/path_provider.dart';

import 'real_push_sync_test.dart' show stateOf;

const bridge = 'http://127.0.0.1:19079';

// Only observes the actual callback. It neither initializes Firebase nor fetches
// data before calling the production handler, and never performs its own sync.
@pragma('vm:entry-point')
Future<void> observeColdPush(RemoteMessage message) async {
  final result = <String, dynamic>{
    'message_id': message.messageId,
    'kind': message.data['kind'],
    'pid': pid,
  };
  final repo = FamilyRepository();
  try {
    await incomingPush(message);
    await repo.initialize();
    result['state'] = stateOf(repo);
  } catch (error) {
    result['error'] = error.runtimeType.toString();
  } finally {
    await repo.db?.close();
    repo.client.close();
    repo.dispose();
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
  testWidgets('persist real FCM registration before process death and reboot', (
    tester,
  ) async {
    final repo = FamilyRepository();
    final services = BackgroundServices(repo);
    final control = http.Client();
    var key = const String.fromEnvironment('COLD_PUSH_RUN');
    Future<Map<String, dynamic>> call(
      String path,
      Map<String, dynamic> body,
    ) async {
      final response = await control
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
      await Firebase.initializeApp();
      expect(Firebase.app().options.projectId, 'mykids-family-ec459');
      final token = await requestFamilyPushTarget().timeout(
        const Duration(seconds: 90),
      );
      final setup = await call('register', {'device_token': token});
      key = setup['client_key'] as String;
      final actor = setup['actor'] as String;
      await repo.initialize(actor == 'kid' ? 'child' : 'parent');
      await repo.login(bridge, actor, 'synthetic-cold-push-12345');
      FirebaseMessaging.onBackgroundMessage(observeColdPush);
      await services.initialize((_) async {});
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!services.pushReady && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(services.pushReady, isTrue);
      await repo.sync();
      await tester.pumpAndSettle();
      await call('ready', {'pid': pid, 'state': stateOf(repo)});
      binding.reportData = {'actor': actor, 'pid': pid, 'bootstrap': true};
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      services.dispose();
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
      control.close();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
