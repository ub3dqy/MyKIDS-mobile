import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/main.dart' show TodayScreen;
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;
import 'cross_device_test.dart' show TestForegroundServices, connect;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'financial actions update three retained sessions without restarting',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      final clients = <String, FamilyRepository>{};
      final services = <String, TestForegroundServices>{};
      final cases = <String>[];
      Timer? fallback;
      var tab = 0;
      late StateSetter select;
      Future<void> show(int value) async {
        select(() => tab = value);
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        await binding.takeScreenshot('finance-sync-$name');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        expect(tester.takeException(), isNull);
      }

      Future<void> assertState(
        int total,
        int reserve,
        int requests,
        int penalties,
      ) async {
        for (final repo in clients.values) {
          final balance = repo.snapshot!['balance'];
          expect(
            [balance['total'], balance['reserved'], balance['available']],
            [total, reserve, total - reserve],
          );
          expect(
            repo
                .rows('redemptions')
                .where((r) => ['pending', 'claimed'].contains(r['status']))
                .length,
            requests,
          );
          expect(
            repo
                .rows('penalties')
                .where((p) => p['status'] == 'pending')
                .length,
            penalties,
          );
        }
        for (final parent in [0, 1]) {
          await show(parent);
          await revealField(
            tester,
            find.text('Заявок на награды и деньги: $requests'),
          );
        }
        await show(2);
        await revealField(
          tester,
          find.text('Всего: $total · в заявках: $reserve'),
        );
        expect(find.text('${total - reserve}'), findsOneWidget);
      }

      Future<Map<String, dynamic>> change(
        String name,
        String actor,
        String path,
        Map<String, dynamic> body,
        int total,
        int reserve,
        int requests, {
        int penalties = 0,
      }) async {
        final result = await clients[actor]!.mutate(path, body);
        // Delivery is simulated; the handler and API, database, money and UI paths are real.
        await Future.wait(
          services.entries
              .where((e) => e.key != actor)
              .map(
                (e) => e.value.handleForegroundMessage(
                  const RemoteMessage(
                    data: {
                      'kind': 'calendar',
                      'entity_id': 'synthetic-finance',
                    },
                  ),
                ),
              ),
        );
        await assertState(total, reserve, requests, penalties);
        cases.add(name);
        return result;
      }

      try {
        for (final name in ['papa', 'mama', 'kid']) {
          clients[name] = await connect(name);
          services[name] = TestForegroundServices(clients[name]!);
        }
        final identities = {
          for (final e in clients.entries) e.key: e.value.sessionTag,
        };
        final papa = clients['papa']!,
            mama = clients['mama']!,
            kid = clients['kid']!;
        final task =
            (await papa.mutate('/v1/tasks', {
                  'title': 'Начальный заработок',
                  'due_at': DateTime.now()
                      .toUtc()
                      .add(const Duration(days: 1))
                      .toIso8601String(),
                  'reward': 200,
                  'is_required': false,
                }))['ids'][0]
                as String;
        await kid.mutate('/v1/tasks/$task/submissions', {
          'task_version': 1,
          'marked_at': DateTime.now().toUtc().toIso8601String(),
        });
        await papa.mutate('/v1/tasks/$task/actions', {
          'action': 'approve',
          'task_version': 1,
        });
        await Future.wait(clients.values.map((r) => r.sync()));
        final merged = Listenable.merge(clients.values.toList());
        await mountFields(
          tester,
          StatefulBuilder(
            builder: (_, state) {
              select = state;
              return Scaffold(
                body: AnimatedBuilder(
                  animation: merged,
                  builder: (_, _) => IndexedStack(
                    index: tab,
                    children: [
                      TodayScreen(repository: papa, openPage: (_) {}),
                      TodayScreen(repository: mama, openPage: (_) {}),
                      for (final repo in [kid, papa, mama])
                        MoneyScreen(
                          repository: repo,
                          perform: (_) async =>
                              fail('Viewing must not move money'),
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
        final reward = (await papa.mutate('/v1/rewards', {
          'title': 'Семейная награда',
          'price': 25,
        }))['id'];
        final first = (await change(
          'request_reward',
          'kid',
          '/v1/redemptions',
          {'reward_id': reward},
          200,
          25,
          1,
        ))['id'];
        await change(
          'claim_reward',
          'papa',
          '/v1/redemptions/$first/actions',
          {'action': 'claim'},
          200,
          25,
          1,
        );
        await change(
          'confirm_reward',
          'papa',
          '/v1/redemptions/$first/actions',
          {'action': 'confirm'},
          175,
          0,
          0,
        );
        await show(1);
        await capture('parent-payout');
        await papa.mutate('/v1/redemptions/$first/actions', {
          'action': 'confirm',
        });
        expect(
          papa.rows('ledger').where((e) => e['source_id'] == first).length,
          1,
        );
        final second = (await change(
          'request_cash',
          'kid',
          '/v1/redemptions',
          {'amount': 50},
          175,
          50,
          1,
        ))['id'];
        await change(
          'child_cancel',
          'kid',
          '/v1/redemptions/$second/actions',
          {'action': 'cancel'},
          175,
          0,
          0,
        );
        final third = (await change(
          'request_again',
          'kid',
          '/v1/redemptions',
          {'amount': 30},
          175,
          30,
          1,
        ))['id'];
        await change(
          'other_parent_claim',
          'mama',
          '/v1/redemptions/$third/actions',
          {'action': 'claim'},
          175,
          30,
          1,
        );
        await change(
          'release_claim',
          'mama',
          '/v1/redemptions/$third/actions',
          {'action': 'release'},
          175,
          30,
          1,
        );
        await change(
          'reclaim',
          'papa',
          '/v1/redemptions/$third/actions',
          {'action': 'claim'},
          175,
          30,
          1,
        );
        await change(
          'parent_reject',
          'papa',
          '/v1/redemptions/$third/actions',
          {'action': 'reject'},
          175,
          0,
          0,
        );
        final lost = (await kid.mutate('/v1/redemptions', {
          'amount': 10,
        }))['id'];
        await Future.wait(clients.values.map((r) => r.sync()));
        await kid.mutate('/v1/redemptions/$lost/actions', {'action': 'cancel'});
        expect(mama.snapshot!['balance']['reserved'], 10);
        final recovered = Completer<void>();
        fallback = Timer.periodic(const Duration(seconds: 3), (_) async {
          await Future.wait([papa.sync(), mama.sync()]);
          if (!recovered.isCompleted) recovered.complete();
        });
        await recovered.future.timeout(const Duration(seconds: 15));
        fallback.cancel();
        await assertState(175, 0, 0, 0);
        final subject = (await papa.mutate('/v1/subjects', {
          'name': 'Математика',
        }))['id'];
        await papa.mutate('/v1/grade-rules', {
          'amounts': {'2': -40},
        }, method: 'PUT');
        final grade = (await papa.mutate('/v1/grades', {
          'subject_id': subject,
          'date': '2026-10-16',
          'grade': 2,
        }))['id'];
        await Future.wait(clients.values.map((r) => r.sync()));
        await assertState(175, 0, 0, 1);
        final gradeFine = papa
            .rows('penalties')
            .singleWhere((p) => p['source_id'] == grade)['id'];
        await change(
          'grade_penalty',
          'mama',
          '/v1/penalties/$gradeFine/approve',
          {},
          135,
          0,
          0,
        );
        final lateTask =
            (await papa.mutate('/v1/tasks', {
                  'title': 'Просроченное обязательное задание',
                  'due_at': DateTime.now()
                      .toUtc()
                      .subtract(const Duration(days: 2))
                      .toIso8601String(),
                  'is_required': true,
                  'penalty': 200,
                }))['ids'][0]
                as String;
        await Future.wait(clients.values.map((r) => r.sync()));
        final taskFine = papa
            .rows('penalties')
            .singleWhere((p) => p['source_id'] == lateTask)['id'];
        await change(
          'task_penalty_negative_balance',
          'papa',
          '/v1/penalties/$taskFine/approve',
          {},
          -65,
          0,
          0,
        );
        await mama.mutate('/v1/penalties/$taskFine/approve', {});
        expect(
          mama.rows('ledger').where((e) => e['source_id'] == lateTask).length,
          1,
        );
        for (final page in [3, 4]) {
          await show(page);
          await revealField(
            tester,
            find.text('Всего: -65 · в заявках: 0 · доступно: -65'),
          );
          await revealField(tester, find.text('Штрафы ждут подтверждения: 0'));
          expect(find.text('Штрафы ждут подтверждения: 0'), findsOneWidget);
        }
        await capture('parent-penalty');
        await show(2);
        await revealField(tester, find.text('Всего: -65 · в заявках: 0'));
        await capture('child');
        for (final entry in clients.entries) {
          expect(entry.value.sessionTag, identities[entry.key]);
        }
        binding.reportData = {
          ...?binding.reportData,
          'synthetic_only': true,
          'real_local_api': true,
          'independent_client_sessions': 3,
          'clients_restarted': false,
          'fcm_transport_tested': false,
          'physical_devices_tested': false,
          'cases': cases,
          'lost_push_polling_recovered': true,
          'no_double_debit': true,
          'negative_balance_verified': true,
          'mobile_source_version': '0.1.34',
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
    },
  );
}
