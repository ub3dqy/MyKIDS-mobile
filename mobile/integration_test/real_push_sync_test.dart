import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mykids_family/push_registration.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/main.dart' show TodayScreen;
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';

const bridge = 'http://127.0.0.1:19079';

Map<String, dynamic> stateOf(FamilyRepository repo) => {
  'balance': {
    for (final key in ['total', 'reserved', 'available'])
      key: repo.snapshot!['balance'][key],
  },
  'tasks': [
    for (final r in repo.rows('tasks')) [r['id'], r['status'], r['version']],
  ],
  'grades': [
    for (final r in repo.rows('grades')) [r['id'], r['grade']],
  ],
  'rewards': [
    for (final r in repo.rows('rewards')) [r['id'], r['price']],
  ],
  'redemptions': [
    for (final r in repo.rows('redemptions'))
      [r['id'], r['status'], r['amount']],
  ],
  'unread': repo
      .rows('rooms')
      .fold<int>(0, (n, r) => n + (r['unread_count'] as int? ?? 0)),
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real FCM updates retained family session and visible screens', (
    tester,
  ) async {
    final control = http.Client();
    final repo = FamilyRepository();
    BackgroundServices? services;
    StreamSubscription<RemoteMessage>? observer;
    String key = const String.fromEnvironment('REAL_PUSH_RUN');
    final received = <String>[];
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

    var baseline = 0, tab = 0;
    late StateSetter select;
    try {
      await Firebase.initializeApp();
      expect(Firebase.app().options.projectId, 'mykids-family-ec459');
      String? token;
      for (var attempt = 0; attempt < 3 && token == null; attempt++) {
        try {
          token = await requestFamilyPushTarget().timeout(
            const Duration(seconds: 40),
          );
        } catch (_) {
          if (attempt == 2) rethrow;
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
      expect(token, isNotNull);
      final setup = await call('register', {'device_token': token});
      key = setup['client_key'] as String;
      final actor = setup['actor'] as String;
      await repo.initialize(actor == 'kid' ? 'child' : 'parent');
      await repo.login(bridge, actor, 'synthetic-real-push-12345');
      // Use the production Firebase listener; never invoke its callback in this test.
      services = BackgroundServices(repo);
      await services.initialize((_) {});
      observer = FirebaseMessaging.onMessage.listen((message) {
        received.add(message.messageId ?? 'missing-message-id');
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('ru')],
          home: StatefulBuilder(
            builder: (context, update) {
              select = update;
              return Scaffold(
                body: AnimatedBuilder(
                  animation: repo,
                  builder: (_, _) => switch (tab) {
                    1 => MoneyScreen(
                      repository: repo,
                      perform: (_) async => fail('Read-only screen'),
                    ),
                    2 => FamilyScreen(
                      repository: repo,
                      perform: (_) async => fail('Read-only screen'),
                    ),
                    _ => TodayScreen(repository: repo, openPage: (_) {}),
                  },
                ),
              );
            },
          ),
        ),
      );
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
          baseline = received.length;
          await call('reply', {'id': id, 'received': baseline});
        } else if (type == 'command') {
          final result = await repo.mutate(
            command['path'] as String,
            Map<String, dynamic>.from(command['body'] as Map),
            method: command['method'] as String? ?? 'POST',
          );
          await call('reply', {'id': id, 'result': result});
        } else if (type == 'assert') {
          final expected = command['expected'];
          final deadline = DateTime.now().add(const Duration(seconds: 65));
          bool matches() =>
              jsonEncode(stateOf(repo)) == jsonEncode(expected) &&
              (command['requires_push'] != true || received.length > baseline);
          while (!matches() && DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 200));
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          expect(
            stateOf(repo),
            expected,
            reason: 'Real push ${command['phase']} for $actor',
          );
          if (command['requires_push'] == true) {
            expect(received.length, greaterThan(baseline));
          }
          select(() => tab = 1);
          await tester.pumpAndSettle();
          final balance = repo.snapshot!['balance'];
          expect(
            find.textContaining(
              'Всего: ${balance['total']} · в заявках: ${balance['reserved']}',
            ),
            findsOneWidget,
          );
          select(() => tab = 0);
          await tester.pumpAndSettle();
          final waiting = repo
              .rows('tasks')
              .where((r) => r['status'] == 'submitted')
              .length;
          if (actor != 'kid') {
            expect(
              find.text('Результатов на проверке: $waiting'),
              findsOneWidget,
            );
          }
          select(() => tab = 2);
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
            'received': received.length,
            'new_messages': received.skip(baseline).toList(),
            'state': stateOf(repo),
            'screens_checked': true,
          });
        }
      }
      binding.reportData = {
        'actor': actor,
        'pid': pid,
        'checks': checks,
        'real_fcm_received': received.length,
        'fallback_polling': false,
        'physical_phone': false,
      };
    } catch (error) {
      await call('failure', {
        'error': error.runtimeType.toString(),
      }).catchError((_) => <String, dynamic>{});
      rethrow;
    } finally {
      await observer?.cancel();
      services?.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
      control.close();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
