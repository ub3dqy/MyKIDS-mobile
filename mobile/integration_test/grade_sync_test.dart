import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/school_screen.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;
import 'cross_device_test.dart' show TestForegroundServices, connect;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('grade changes update three retained clients and money', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final clients = <String, FamilyRepository>{};
    final services = <String, TestForegroundServices>{};
    final cases = <String>[];
    Timer? fallback;
    var tab = 0;
    String? gradeId;
    late StateSetter select;
    Future<void> show(int value) async {
      select(() => tab = value);
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

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await binding.takeScreenshot('grade-sync-$name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(tester.takeException(), isNull);
    }

    Future<void> assertState(
      int grade,
      int coins, {
      int pending = 0,
      String? note,
    }) async {
      for (final repo in clients.values) {
        final row = repo.rows('grades').singleWhere((g) => g['id'] == gradeId);
        expect(row['grade'], grade);
        if (note != null) {
          expect(row['note'], note);
        }
        expect(repo.snapshot!['balance']['total'], coins);
        expect(repo.snapshot!['balance']['available'], coins);
        expect(repo.snapshot!['balance']['reserved'], 0);
        expect(
          repo.rows('penalties').where((p) => p['status'] == 'pending').length,
          pending > 0 ? 1 : 0,
        );
        expect(
          repo
              .rows('penalties')
              .where((p) => p['status'] == 'pending')
              .fold<int>(0, (sum, p) => sum + (p['amount'] as int)),
          pending,
        );
      }
      for (final page in [0, 1, 2]) {
        await show(page);
        await revealField(tester, find.text('Оценка: $grade'));
        if (note != null) {
          expect(find.text(note), findsOneWidget);
        }
      }
      await show(3);
      await revealField(tester, find.text('Всего: $coins · в заявках: 0'));
      expect(find.text('$coins'), findsOneWidget);
      for (final page in [4, 5]) {
        await show(page);
        await revealField(
          tester,
          find.text('Всего: $coins · в заявках: 0 · доступно: $coins'),
        );
      }
      await show(3);
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
      final day = dateOnly(familyClock(papa.snapshot));
      await papa.mutate('/v1/grade-rules', {
        'amounts': {'5': 25, '4': 10, '3': 0, '2': -40},
      }, method: 'PUT');
      final schedule = (await papa.mutate('/v1/schedules', {
        'title': 'Школа',
        'date': day,
        'start': '09:00',
        'end': '10:00',
        'grade_subjects': true,
        'activities': [
          {'title': 'Математика', 'start': '09:00', 'end': '09:45'},
        ],
      }))['id'];
      final row = papa
          .rows('schedules')
          .singleWhere((s) => s['id'] == schedule);
      final activity =
          (jsonDecode(row['activities'] as String) as List).single['id'];
      final source = <String, dynamic>{
        'schedule_id': schedule,
        'activity_id': activity,
        'date': day,
      };
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
                      SchoolScreen(
                        repository: repo,
                        perform: (action) async {
                          await action();
                        },
                      ),
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
      Future<void> save(
        String name,
        String actor,
        int value,
        String note,
        int coins, {
        int pending = 0,
      }) async {
        final result = await clients[actor]!.mutate(
          '/v1/grades${gradeId == null ? '' : '/$gradeId'}',
          {...source, 'grade': value, 'note': note},
          method: gradeId == null ? 'POST' : 'PUT',
        );
        gradeId = result['id'] as String;
        await deliver(actor, gradeId!);
        await assertState(value, coins, pending: pending, note: note);
        cases.add(name);
      }

      await save('add_calendar_grade', 'papa', 4, 'Первая оценка', 10);
      await save('raise_grade', 'mama', 5, 'Исправили на пятёрку', 25);
      await papa.mutate('/v1/grade-rules', {
        'amounts': {'5': 100},
      }, method: 'PUT');
      await save(
        'note_only_no_new_reward',
        'papa',
        5,
        'Уточнённое примечание',
        25,
      );
      expect(papa.rows('grades').single['rule_amount'], 25);
      expect(papa.rows('grades').single['version'], 2);
      await papa.mutate('/v1/grade-rules', {
        'amounts': {'5': 25},
      }, method: 'PUT');
      await save(
        'lower_grade_pending_penalty',
        'mama',
        2,
        'Нужна пересдача',
        25,
        pending: 65,
      );
      for (final page in [4, 5]) {
        await show(page);
        await revealField(tester, find.text('Штрафы ждут подтверждения: 1'));
      }
      await capture('pending-penalty');
      final penalty = papa
          .rows('penalties')
          .singleWhere((p) => p['status'] == 'pending')['id'];
      await papa.mutate('/v1/penalties/$penalty/approve', {});
      await deliver('papa', penalty as String);
      await assertState(2, -40, note: 'Нужна пересдача');
      cases.add('confirmed_penalty');
      await save('correct_after_penalty', 'mama', 5, 'Пересдача принята', 25);
      await save(
        'same_grade_no_double_reward',
        'papa',
        5,
        'Пересдача принята',
        25,
      );
      expect(
        papa.rows('ledger').where((e) => e['source_id'] == gradeId).length,
        4,
      );
      await capture('child-coins');
      final subject = (await papa.mutate('/v1/subjects', {
        'name': 'Русский язык',
      }))['id'];
      final freeSource = <String, dynamic>{
        'subject_id': subject,
        'date': day,
        'grade': 3,
      };
      final saved =
          (await mama.mutate('/v1/grades', {
                ...freeSource,
                'note': 'Сохранённая оценка',
              }))['id']
              as String;
      await deliver('mama', saved);
      for (final page in [0, 1, 2]) {
        await show(page);
        await revealField(tester, find.text('Русский язык · 3'));
        expect(find.text('Сохранённая оценка'), findsOneWidget);
      }
      cases.add('zero_reward_history_grade');
      final next = dateOnly(
        familyClock(papa.snapshot).add(const Duration(days: 1)),
      );
      await papa.mutate('/v1/grades/$saved', {
        ...freeSource,
        'date': next,
        'note': 'Дата исправлена',
      }, method: 'PUT');
      await deliver('papa', saved);
      for (final entry in clients.entries) {
        expect(
          entry.value
              .rows('grades')
              .singleWhere((g) => g['id'] == saved)['date'],
          next,
        );
      }
      for (final page in [0, 1, 2]) {
        await show(page);
        expect(find.text('Русский язык · 3'), findsNothing);
      }
      cases.add('history_date_change');
      await mama.mutate('/v1/grades/$saved', {
        ...freeSource,
        'note': 'Дата возвращена',
      }, method: 'PUT');
      await deliver('mama', saved);
      await papa.mutate('/v1/grades/$saved', {
        ...freeSource,
        'note': 'Без уведомления',
      }, method: 'PUT');
      expect(
        mama.rows('grades').singleWhere((g) => g['id'] == saved)['note'],
        'Дата возвращена',
      );
      final recovered = Completer<void>();
      fallback = Timer.periodic(const Duration(seconds: 3), (_) async {
        await Future.wait([mama.sync(), kid.sync()]);
        if (!recovered.isCompleted) {
          recovered.complete();
        }
      });
      await recovered.future.timeout(const Duration(seconds: 15));
      fallback.cancel();
      for (final page in [0, 1, 2]) {
        await show(page);
        await revealField(tester, find.text('Без уведомления'));
      }
      await capture('history');
      for (final entry in clients.entries) {
        expect(entry.value.snapshot!['balance']['total'], 25);
        expect(entry.value.rows('grades').length, 2);
        expect(entry.value.sessionTag, identities[entry.key]);
        expect(
          entry.value.rows('ledger').where((e) => e['source_id'] == saved),
          isEmpty,
        );
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
        'notes_do_not_reapply_rules': true,
        'no_double_reward': true,
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
  });
}
