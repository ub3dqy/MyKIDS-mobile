import 'dart:convert';
import 'dart:io';

import 'package:mykids_family/push_registration.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:path_provider/path_provider.dart';

import 'real_push_sync_test.dart' show stateOf;

const bridge = 'http://127.0.0.1:19079';

// Test-only observer of a real Google delivery in FlutterFire's background
// isolate. It calls the released handler, then reads its persisted result.
// It never fetches a snapshot or calls sync itself.
@pragma('vm:entry-point')
Future<void> observeBackgroundPush(RemoteMessage message) async {
  await Firebase.initializeApp();
  final record = <String, dynamic>{
    'message_id': message.messageId,
    'kind': message.data['kind'],
    'pid': pid,
  };
  final repository = FamilyRepository();
  try {
    await incomingPush(message);
    await repository.initialize();
    record['state'] = stateOf(repository);
  } catch (error) {
    record['error'] = error.runtimeType.toString();
  } finally {
    await repository.db?.close();
    repository.client.close();
    repository.dispose();
    final folder = await getApplicationSupportDirectory();
    await File('${folder.path}/background-push.jsonl').writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual FCM while Home and keyguard retain all three sessions', (
    tester,
  ) async {
    final control = http.Client();
    final repo = FamilyRepository();
    var key = const String.fromEnvironment('BACKGROUND_PUSH_RUN');
    final checks = <String>[];
    Future<Map<String, dynamic>> call(
      String path, [
      Map<String, dynamic>? body,
    ]) async {
      final response = await control
          .post(
            Uri.parse('$bridge/__probe/$path'),
            headers: {'Content-Type': 'application/json', 'X-Real-Push': key},
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 15));
      expect(response.statusCode, 200, reason: 'Probe $path');
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }

    try {
      await Firebase.initializeApp();
      expect(Firebase.app().options.projectId, 'mykids-family-ec459');
      final token = await requestFamilyPushTarget().timeout(
        const Duration(seconds: 90),
      );
      expect(token, isNotNull);
      final setup = await call('register', {'device_token': token});
      key = setup['client_key'] as String;
      final actor = setup['actor'] as String;
      await repo.initialize(actor == 'kid' ? 'child' : 'parent');
      await repo.login(bridge, actor, 'synthetic-real-push-12345');
      final folder = await getApplicationSupportDirectory();
      final audit = File('${folder.path}/background-push.jsonl');
      if (await audit.exists()) await audit.delete();
      FirebaseMessaging.onBackgroundMessage(observeBackgroundPush);
      final services = BackgroundServices(repo);
      await tester.pumpWidget(
        MyKidsApp(
          repository: repo,
          createBackground: (_) => services,
          now: () => DateTime.utc(2026, 10, 17, 17),
        ),
      );
      final ready = DateTime.now().add(const Duration(seconds: 60));
      while (!services.pushReady && DateTime.now().isBefore(ready)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(services.pushReady, isTrue);
      await tester.pumpAndSettle();
      await call('online', {'pid': pid, 'state': stateOf(repo)});
      while (true) {
        final command = await call('next');
        final type = command['type'];
        if (type == 'idle') {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        if (type == 'finish') break;
        final id = command['id'];
        if (type == 'barrier') {
          await call('reply', {'id': id});
        } else if (type == 'command') {
          final result = await repo.mutate(
            command['path'] as String,
            Map<String, dynamic>.from(command['body'] as Map),
            method: command['method'] as String? ?? 'POST',
          );
          await call('reply', {'id': id, 'result': result});
        } else if (type == 'assert') {
          final expected = command['expected'];
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          // The real MyKidsApp lifecycle observer performs the resume refresh.
          // There is no test-side sync or artificial lifecycle callback here.
          while ((jsonEncode(stateOf(repo)) != jsonEncode(expected) ||
                  binding.lifecycleState != AppLifecycleState.resumed) &&
              DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 200));
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          expect(stateOf(repo), expected, reason: '${command['phase']} $actor');
          expect(binding.lifecycleState, AppLifecycleState.resumed);
          await tester.pumpAndSettle();
          // A real approval celebration can cover the navigation bar.
          final dialog = find.byType(AlertDialog);
          if (dialog.evaluate().isNotEmpty) {
            await tester.tap(find.widgetWithText(FilledButton, 'Здорово!'));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.widgetWithText(TextButton, 'Монеты').last);
          await tester.pumpAndSettle();
          final balance = repo.snapshot!['balance'];
          expect(
            find.textContaining(
              'Всего: ${balance['total']} · в заявках: ${balance['reserved']}',
            ),
            findsOneWidget,
          );
          await tester.tap(find.widgetWithText(TextButton, 'Сегодня').last);
          await tester.pumpAndSettle();
          if (actor != 'kid') {
            final waiting = repo
                .rows('tasks')
                .where((r) => r['status'] == 'submitted')
                .length;
            expect(
              find.text('Результатов на проверке: $waiting'),
              findsOneWidget,
            );
          }
          await tester.tap(find.widgetWithText(TextButton, 'Семья').last);
          await tester.pumpAndSettle();
          final unread = expected['unread'] as int;
          if (unread > 0) {
            expect(
              find.byWidgetPredicate(
                (w) =>
                    w is Semantics &&
                    w.properties.label == 'Непрочитанных сообщений: $unread',
              ),
              findsOneWidget,
            );
          }
          checks.add(command['phase'] as String);
          await call('reply', {
            'id': id,
            'pid': pid,
            'state': stateOf(repo),
            'screens_checked': true,
          });
        }
      }
      binding.reportData = {
        'actor': actor,
        'pid': pid,
        'checks': checks,
        'real_background_delivery': true,
        'physical_phone': false,
      };
    } catch (error) {
      await call('failure', {
        'error': error.runtimeType.toString(),
      }).catchError((_) => <String, dynamic>{});
      rethrow;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
      control.close();
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
