import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;
import 'cross_device_test.dart' show TestForegroundServices, connect;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('reward catalogue and prices update on three retained clients', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final clients = <String, FamilyRepository>{};
    final services = <String, TestForegroundServices>{};
    final cases = <String>[];
    Timer? fallback;
    var tab = 0;
    late StateSetter select;
    Future<void> show(int page) async {
      select(() => tab = page);
      await tester.pumpAndSettle();
    }

    Future<void> deliver(String actor, String id) async {
      await Future.wait(
        services.entries
            .where((e) => e.key != actor)
            .map(
              (e) => e.value.handleForegroundMessage(
                RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
              ),
            ),
      );
    }

    Future<void> until(bool Function() ready) async {
      for (var i = 0; i < 120 && !ready(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(ready(), isTrue);
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await binding.takeScreenshot('reward-sync-$name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(tester.takeException(), isNull);
    }

    Future<void> title(String label, {bool childVisible = true}) async {
      for (final page in [0, 1, 2]) {
        await show(page);
        if (page == 2 && !childVisible) {
          expect(find.text(label), findsNothing);
        } else {
          await revealField(tester, find.text(label));
          expect(find.text(label), findsOneWidget);
        }
      }
    }

    void finances(int total, int reserved) {
      for (final repo in clients.values) {
        final balance = repo.snapshot!['balance'];
        expect(
          (balance['total'], balance['reserved'], balance['available']),
          (total, reserved, total - reserved),
        );
      }
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
          ((await papa.mutate('/v1/tasks', {
                        'title': 'Тестовая награда за задание',
                        'due_at': DateTime.now()
                            .toUtc()
                            .add(const Duration(days: 1))
                            .toIso8601String(),
                        'reward': 100,
                        'is_required': false,
                      }))['ids']
                      as List)
                  .single
              as String;
      await kid.mutate('/v1/tasks/$task/submissions', {
        'task_version': 1,
        'marked_at': DateTime.now().toUtc().toIso8601String(),
      });
      await papa.mutate('/v1/tasks/$task/actions', {'action': 'approve'});
      await Future.wait(clients.values.map((r) => r.sync()));
      await mountFields(
        tester,
        StatefulBuilder(
          builder: (_, state) {
            select = state;
            return Scaffold(
              body: AnimatedBuilder(
                animation: Listenable.merge(clients.values.toList()),
                builder: (_, _) => IndexedStack(
                  index: tab,
                  children: [
                    for (final repo in clients.values)
                      MoneyScreen(
                        repository: repo,
                        perform: (action) async {
                          await action();
                        },
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
      var body = <String, dynamic>{
        'title': 'Конструктор',
        'description': 'Первая награда',
        'price': 40,
        'available': true,
      };
      final reward = (await papa.mutate('/v1/rewards', body))['id'] as String;
      await deliver('papa', reward);
      await title('Конструктор · 40 монет');
      finances(100, 0);
      cases.add('create_reward');
      await tester.tap(find.text('Конструктор · 40 монет'));
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Копить на это'));
      await tester.tap(find.text('Копить на это'));
      await until(() => kid.snapshot!['goal']?['reward_id'] == reward);
      await deliver('kid', reward);
      for (final repo in clients.values) {
        expect(repo.snapshot!['goal']['reward_id'], reward);
      }
      cases.add('choose_goal');
      body = {
        ...body,
        'title': 'Большой конструктор',
        'description': 'Новые условия',
        'price': 150,
      };
      await mama.mutate('/v1/rewards/$reward', body, method: 'PUT');
      await deliver('mama', reward);
      await title('Большой конструктор · 150 монет');
      await revealField(tester, find.text('До цели ещё 50 монет'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Попросить награду'),
            )
            .onPressed,
        isNull,
      );
      finances(100, 0);
      await capture('child-price-goal');
      cases.add('increase_price_and_goal_progress');
      body = {...body, 'description': 'Подробное описание'};
      await papa.mutate('/v1/rewards/$reward', body, method: 'PUT');
      await deliver('papa', reward);
      for (final repo in clients.values) {
        expect(
          repo.rows('rewards').single['description'],
          'Подробное описание',
        );
      }
      cases.add('edit_description');
      body = {...body, 'available': false};
      await papa.mutate('/v1/rewards/$reward', body, method: 'PUT');
      await deliver('papa', reward);
      await title('Большой конструктор · 150 монет', childVisible: false);
      cases.add('hide_reward');
      body = {...body, 'available': true};
      await mama.mutate('/v1/rewards/$reward', body, method: 'PUT');
      await deliver('mama', reward);
      await title('Большой конструктор · 150 монет');
      cases.add('restore_reward');
      body = {...body, 'price': 25};
      await papa.mutate('/v1/rewards/$reward', body, method: 'PUT');
      await deliver('papa', reward);
      await title('Большой конструктор · 25 монет');
      await revealField(tester, find.text('Попросить награду'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Попросить награду'),
            )
            .onPressed,
        isNotNull,
      );
      cases.add('decrease_price_and_request_button');
      await tester.tap(find.text('Попросить награду'));
      await until(() => kid.rows('redemptions').isNotEmpty);
      final request = kid.rows('redemptions').single['id'] as String;
      await deliver('kid', request);
      finances(100, 25);
      cases.add('request_keeps_displayed_price');
      body = {...body, 'price': 150};
      await mama.mutate('/v1/rewards/$reward', body, method: 'PUT');
      await deliver('mama', reward);
      await title('Большой конструктор · 150 монет');
      for (final repo in clients.values) {
        expect(repo.rows('redemptions').single['amount'], 25);
      }
      await show(0);
      await revealField(tester, find.text('Большой конструктор · 150 монет'));
      await tester.tap(find.text('Большой конструктор · 150 монет'));
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Удалить награду'));
      await tester.tap(find.text('Удалить награду'));
      await tester.pumpAndSettle();
      body = {...body, 'title': 'Изменённая награда', 'price': 90};
      await mama.mutate('/v1/rewards/$reward', body, method: 'PUT');
      await deliver('mama', reward);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Изменённая награда · 90 монет\n'),
        findsOneWidget,
      );
      await capture('parent-delete-confirmation');
      cases.add('open_confirmation_updates');
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await until(() => papa.rows('rewards').isEmpty);
      await deliver('papa', reward);
      for (final repo in clients.values) {
        expect(repo.rows('rewards'), isEmpty);
        expect(repo.snapshot!['goal'], isNull);
        final old = repo.rows('redemptions').single;
        expect(
          (old['title'], old['amount'], old['status'], old['reward_id']),
          ('Большой конструктор', 25, 'pending', null),
        );
      }
      finances(100, 25);
      await show(2);
      await revealField(tester, find.text('Большой конструктор · 25'));
      await capture('deleted-with-existing-request');
      cases.add('delete_keeps_request_and_balance');
      await papa.mutate('/v1/redemptions/$request/actions', {
        'action': 'claim',
      });
      await deliver('papa', request);
      await papa.mutate('/v1/redemptions/$request/actions', {
        'action': 'confirm',
      });
      await deliver('papa', request);
      finances(75, 0);
      cases.add('fulfil_deleted_reward_at_agreed_price');
      final other =
          (await mama.mutate('/v1/rewards', {
                'title': 'Велосипед',
                'price': 200,
              }))['id']
              as String;
      await deliver('mama', other);
      await title('Велосипед · 200 монет');
      await show(0);
      await revealField(tester, find.text('Велосипед · 200 монет'));
      await tester.tap(find.text('Велосипед · 200 монет'));
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Удалить награду'));
      await tester.tap(find.text('Удалить награду'));
      await tester.pumpAndSettle();
      await mama.mutate('/v1/rewards/$other', {}, method: 'DELETE');
      await deliver('mama', other);
      await tester.pumpAndSettle();
      expect(
        find.text('Награда уже удалена или доступ изменился'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Удалить'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      cases.add('external_delete_disables_confirmation');
      final lost =
          (await papa.mutate('/v1/rewards', {
                'title': 'Книга',
                'price': 80,
              }))['id']
              as String;
      expect(mama.rows('rewards'), isEmpty);
      final recovered = Completer<void>();
      fallback = Timer.periodic(const Duration(seconds: 3), (_) async {
        await Future.wait([mama.sync(), kid.sync()]);
        if (!recovered.isCompleted) recovered.complete();
      });
      await recovered.future.timeout(const Duration(seconds: 15));
      fallback.cancel();
      await title('Книга · 80 монет');
      finances(75, 0);
      cases.add('lost_signal_polling');
      await mama.mutate('/v1/rewards/$lost', {}, method: 'DELETE');
      await deliver('mama', lost);
      for (final entry in clients.entries) {
        expect(entry.value.sessionTag, identities[entry.key]);
        expect(entry.value.rows('rewards'), isEmpty);
        expect(
          entry.value
              .rows('ledger')
              .where((r) => r['source_id'] == request)
              .single['actual'],
          -25,
        );
      }
      cases.add('delete_by_other_parent');
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'real_local_api': true,
        'independent_client_sessions': 3,
        'clients_restarted': false,
        'cases': cases,
        'request_price_preserved': true,
        'no_unexpected_money_changes': true,
        'lost_push_polling_recovered': true,
        'physical_devices_tested': false,
        'fcm_transport_tested': false,
        'mobile_source_version': '0.1.36',
      };
    } finally {
      fallback?.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
      for (final service in services.values) {
        service.dispose();
      }
      await Future.wait(clients.values.map((repo) => repo.sync()));
      for (final repo in clients.values) {
        await repo.db?.close();
        repo.client.close();
        repo.dispose();
      }
    }
  });
}
