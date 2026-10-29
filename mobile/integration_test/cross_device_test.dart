import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/main.dart' show TodayScreen;
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite/sqflite.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;

class TestForegroundServices extends BackgroundServices {
  TestForegroundServices(super.repository);
  @override
  Future<void> reminders() async {}
}

Future<FamilyRepository> connect(String username) async {
  final repo = FamilyRepository()..endpoint = 'http://127.0.0.1:19076';
  final login = await repo.request(
    '/v1/login',
    method: 'POST',
    body: {'username': username, 'password': 'synthetic-family-only-123'},
  );
  repo.token = login['token'] as String;
  repo.db = await openDatabase(
    inMemoryDatabasePath,
    singleInstance: false,
    version: 1,
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE cache (id INTEGER PRIMARY KEY, data TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE identity (id INTEGER PRIMARY KEY, tag TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE outbox (id TEXT PRIMARY KEY, path TEXT NOT NULL, method TEXT NOT NULL, body TEXT NOT NULL, files TEXT NOT NULL, state TEXT NOT NULL, error TEXT, lease_until INTEGER NOT NULL DEFAULT 0, auth_tag TEXT NOT NULL, lease_owner TEXT NOT NULL DEFAULT \'\')',
      );
    },
  );
  await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
  await repo.sync();
  expect(repo.online, true);
  return repo;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('three persistent clients update after either parent reviews', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final clients = <String, FamilyRepository>{};
    final services = <String, TestForegroundServices>{};
    Timer? fallback;
    var tab = 0;
    late StateSetter select;
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await binding.takeScreenshot('cross-device-$name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(tester.takeException(), isNull);
    }

    Future<void> show(int value) async {
      select(() => tab = value);
      await tester.pumpAndSettle();
    }

    try {
      for (final name in ['papa', 'mama', 'kid']) {
        clients[name] = await connect(name);
        services[name] = TestForegroundServices(clients[name]!);
      }
      final papa = clients['papa']!,
          mama = clients['mama']!,
          kid = clients['kid']!;
      final identities = {
        for (final entry in clients.entries) entry.key: entry.value.sessionTag,
      };
      final merged = Listenable.merge(clients.values.toList());
      await mountFields(
        tester,
        StatefulBuilder(
          builder: (context, state) {
            select = state;
            return Scaffold(
              body: AnimatedBuilder(
                animation: merged,
                builder: (_, _) => IndexedStack(
                  index: tab,
                  children: [
                    TodayScreen(repository: papa, openPage: (_) {}),
                    TodayScreen(repository: mama, openPage: (_) {}),
                    ChildToday(repository: kid, openPage: (_) {}),
                    MoneyScreen(
                      repository: kid,
                      perform: (_) async => fail('Viewing must not move money'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        scale: 1.2,
        screenSize: null,
      );
      var total = 0;
      final cases = <Map<String, dynamic>>[];
      for (final count in [6, 5, 4]) {
        final created = await papa.mutate('/v1/tasks', {
          'title': 'Математика: решено $count из 6',
          'due_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'planned_start': DateTime.now().toUtc().toIso8601String(),
          'planned_end': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .toIso8601String(),
          'reward_options': {
            'total': 6,
            'tiers': [
              {'minimum': 6, 'coins': 50},
              {'minimum': 5, 'coins': 25},
            ],
          },
          'is_required': false,
        });
        final id = (created['ids'] as List).single as String;
        await kid.mutate('/v1/tasks/$id/submissions', {
          'task_version': 1,
          'marked_at': DateTime.now().toUtc().toIso8601String(),
        }, offlineSubmission: true);
        await Future.wait(clients.values.map((r) => r.sync()));
        await show(1);
        await revealField(
          tester,
          find.text('Результатов на проверке: 1').hitTestable(),
        );
        final actor = count == 5 ? mama : papa;
        final watch = Stopwatch()..start();
        await actor.mutate('/v1/tasks/$id/actions', {
          'action': 'approve',
          'task_version': 1,
          'completed_count': count,
        });
        // Simulate delivery of the server's silent calendar event; real FCM
        // transport and physical phones are not part of this emulator test.
        await Future.wait(
          services.entries
              .where((e) => !identical(e.value.repository, actor))
              .map(
                (e) => e.value.handleForegroundMessage(
                  RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
                ),
              ),
        );
        watch.stop();
        total += count == 6
            ? 50
            : count == 5
            ? 25
            : 0;
        for (final repo in clients.values) {
          expect(
            repo.rows('tasks').where((t) => t['status'] == 'submitted'),
            isEmpty,
          );
          expect(repo.snapshot!['balance']['available'], total);
          expect(
            repo.rows('tasks').singleWhere((t) => t['id'] == id)['status'],
            'completed',
          );
          expect(
            repo.rows('ledger').where((e) => e['source_id'] == id).length,
            count >= 5 ? 1 : 0,
          );
        }
        await tester.pumpAndSettle();
        expect(
          find.text('Результатов на проверке: 0').hitTestable(),
          findsOneWidget,
        );
        if (count == 4) {
          await capture('parent');
          await show(2);
          await revealField(tester, find.text('Проверено 3 из 3'));
          expect(
            find.textContaining('На проверке:').hitTestable(),
            findsNothing,
          );
          await capture('child');
          await show(3);
          await revealField(tester, find.text('Всего: 75 · в заявках: 0'));
          await capture('coins');
        }
        cases.add({
          'reviewer': count == 5 ? 'mama' : 'papa',
          'completed_count': count,
          'total_coins': total,
          'update_elapsed_ms': watch.elapsedMilliseconds,
        });
      }
      // A lost push still recovers through the same 3-second polling cadence
      // used by MyKidsApp, without replacing any client or rebuilding its session.
      final task =
          (await papa.mutate('/v1/tasks', {
                'title': 'Проверка без уведомления',
                'reward': 10,
                'is_required': false,
                'due_at': DateTime.now()
                    .toUtc()
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
              }))['ids'][0]
              as String;
      await kid.mutate('/v1/tasks/$task/submissions', {
        'task_version': 1,
        'marked_at': DateTime.now().toUtc().toIso8601String(),
      });
      await Future.wait(clients.values.map((r) => r.sync()));
      await papa.mutate('/v1/tasks/$task/actions', {
        'action': 'approve',
        'task_version': 1,
      });
      expect(kid.snapshot!['balance']['available'], 75);
      final recovered = Completer<void>();
      fallback = Timer.periodic(const Duration(seconds: 3), (_) async {
        await Future.wait([mama.sync(), kid.sync()]);
        if (!recovered.isCompleted) recovered.complete();
      });
      await recovered.future.timeout(const Duration(seconds: 15));
      fallback.cancel();
      for (final entry in clients.entries) {
        expect(entry.value.snapshot!['balance']['available'], 85);
        expect(entry.value.sessionTag, identities[entry.key]);
      }
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'real_local_api': true,
        'independent_client_sessions': 3,
        'clients_restarted': false,
        'physical_devices_tested': false,
        'fcm_transport_tested': false,
        'cases': cases,
        'lost_push_polling_recovered': true,
        'duplicate_reward_entries': false,
      };
    } finally {
      fallback?.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
      for (final service in services.values) {
        service.dispose();
      }
      for (final repo in clients.values) {
        await repo.db?.close();
        repo.client.close();
        repo.dispose();
      }
    }
  });
}
