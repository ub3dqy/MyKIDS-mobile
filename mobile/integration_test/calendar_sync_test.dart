import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/main.dart' show TodayScreen;
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:timezone/timezone.dart' as tz;

import '../test/field_layout_test.dart' show mountFields, revealField;
import 'cross_device_test.dart' show TestForegroundServices, connect;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('task and calendar edits update three retained clients', (
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

    Future<void> titleOn(
      List<int> pages,
      String title, {
      bool present = true,
    }) async {
      for (final page in pages) {
        await show(page);
        final found = find.text(title);
        if (present) {
          await revealField(tester, found.first);
          expect(found, findsWidgets);
        } else {
          expect(found, findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await binding.takeScreenshot('calendar-sync-$name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(tester.takeException(), isNull);
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
      final now = familyClock(papa.snapshot);
      final day = tz.TZDateTime(now.location, now.year, now.month, now.day);
      final tomorrow = tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day + 1,
      );
      final date = dateOnly(day);
      String instant(int hour, [int minute = 0]) => tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      ).toUtc().toIso8601String();
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
                      TaskScreen(
                        repository: repo,
                        perform: (action) async {
                          await action();
                        },
                      ),
                    for (final repo in clients.values)
                      CalendarScreen(
                        repository: repo,
                        initialDay: day,
                        openTasks: (_) {},
                        perform: (action) async {
                          await action();
                        },
                      ),
                    for (final repo in clients.values)
                      TodayScreen(repository: repo, openPage: (_) {}),
                  ],
                ),
              ),
            );
          },
        ),
        scale: 1.2,
        screenSize: null,
      );
      final initial = <String, dynamic>{
        'title': 'Разобрать книги',
        'description': 'Первая версия',
        'due_at': instant(23, 50),
        'planned_start': instant(9),
        'planned_end': instant(9, 30),
        'is_required': false,
        'reward': 0,
      };
      final task =
          ((await papa.mutate('/v1/tasks', initial))['ids'] as List).single
              as String;
      await deliver('papa', task);
      await titleOn([0, 1, 2, 3, 4, 5, 8], 'Разобрать книги');
      await show(8);
      expect(find.text('Проверено 0 из 1'), findsOneWidget);
      cases.add('create_task');
      await mama.mutate('/v1/tasks/$task', {
        ...initial,
        'title': 'Разобрать учебники',
        'description': 'Новые условия',
        'task_version': 1,
        'planned_start': instant(10),
        'planned_end': instant(10, 30),
      }, method: 'PUT');
      await deliver('mama', task);
      await titleOn([0, 1, 2, 3, 4, 5, 8], 'Разобрать учебники');
      await titleOn([0, 1, 2, 3, 4, 5, 8], 'Разобрать книги', present: false);
      await show(2);
      await revealField(tester, find.text('Разобрать учебники'));
      await capture('task-updated');
      cases.add('edit_task');
      await papa.mutate('/v1/tasks/$task/plan', {
        'planned_start': instant(11),
        'planned_end': instant(11, 30),
        'reminder_minutes': 5,
      }, method: 'PATCH');
      await deliver('papa', task);
      for (final repo in clients.values) {
        final entry = calendarDay(repo.snapshot!, day).single;
        expect(
          (entry.start.hour, entry.start.minute, entry.reminder),
          (11, 0, 5),
        );
      }
      await titleOn([3, 4, 5], 'Разобрать учебники');
      cases.add('plan_task');
      await mama.mutate('/v1/tasks/$task/actions', {
        'action': 'reschedule',
        'due_at': tz.TZDateTime(
          now.location,
          tomorrow.year,
          tomorrow.month,
          tomorrow.day,
          23,
          50,
        ).toUtc().toIso8601String(),
      });
      await deliver('mama', task);
      await titleOn([3, 4, 5, 8], 'Разобрать учебники', present: false);
      for (final repo in clients.values) {
        expect(calendarDay(repo.snapshot!, day), isEmpty);
        expect(calendarDay(repo.snapshot!, tomorrow).single.start.hour, 11);
      }
      cases.add('reschedule_task');
      await papa.mutate('/v1/tasks/$task/plan', {
        'reminder_minutes': null,
      }, method: 'PATCH');
      await deliver('papa', task);
      for (final repo in clients.values) {
        expect(calendarDay(repo.snapshot!, tomorrow).single.deadline, isTrue);
        expect(calendarDay(repo.snapshot!, tomorrow).single.reminder, isNull);
      }
      cases.add('remove_task_plan');
      await mama.mutate('/v1/tasks/$task/actions', {'action': 'cancel'});
      await deliver('mama', task);
      await titleOn(
        [0, 1, 2, 3, 4, 5, 8],
        'Разобрать учебники',
        present: false,
      );
      cases.add('cancel_task');
      final base = <String, dynamic>{
        'title': 'Семейная прогулка',
        'date': date,
        'start': '15:00',
        'end': '16:00',
        'place': 'Парк',
      };
      final schedule =
          (await papa.mutate('/v1/schedules', base))['id'] as String;
      await deliver('papa', schedule);
      await titleOn([3, 4, 5, 6, 7, 8], 'Семейная прогулка');
      cases.add('create_event');
      await mama.mutate('/v1/schedules/$schedule', {
        ...base,
        'title': 'Прогулка у реки',
        'start': '16:00',
        'end': '17:00',
        'place': 'Набережная',
      }, method: 'PUT');
      await deliver('mama', schedule);
      await titleOn([3, 4, 5, 6, 7, 8], 'Прогулка у реки');
      await titleOn([3, 4, 5, 6, 7, 8], 'Семейная прогулка', present: false);
      cases.add('edit_event');
      final replacement = {
        ...base,
        'title': 'Прогулка перенесена',
        'start': '17:00',
        'end': '18:00',
      };
      await papa.mutate('/v1/schedules/$schedule/exceptions', {
        'date': date,
        'replacement': replacement,
      });
      await deliver('papa', schedule);
      await titleOn([3, 4, 5, 6, 7, 8], 'Прогулка перенесена');
      await show(5);
      await revealField(tester, find.text('Прогулка перенесена'));
      await capture('event-replaced');
      cases.add('replace_event_day');
      await mama.mutate('/v1/schedules/$schedule/exceptions', {
        'date': date,
        'replacement': null,
      });
      await deliver('mama', schedule);
      await titleOn([3, 4, 5, 6, 7, 8], 'Прогулка перенесена', present: false);
      cases.add('cancel_event_day');
      await papa.mutate('/v1/schedules/$schedule/exceptions', {
        'date': date,
        'replacement': replacement,
      });
      await deliver('papa', schedule);
      await titleOn([3, 4, 5], 'Прогулка перенесена');
      cases.add('restore_event_day');
      await mama.mutate('/v1/schedules/$schedule', {}, method: 'DELETE');
      await deliver('mama', schedule);
      await titleOn([3, 4, 5, 6, 7, 8], 'Прогулка перенесена', present: false);
      cases.add('archive_event');
      final repeating = {
        ...initial,
        'title': 'Повторяем математику',
        'weekdays': [1, 2, 3, 4, 5, 6, 7],
        'repeat_until': dateOnly(
          tz.TZDateTime(now.location, now.year, now.month, now.day + 2),
        ),
      };
      final ids = (await mama.mutate('/v1/tasks', repeating))['ids'] as List;
      final first = ids.first as String;
      await deliver('mama', first);
      await titleOn([0, 1, 2, 3, 4, 5, 8], 'Повторяем математику');
      cases.add('create_repeating_task');
      final edited = await papa.mutate('/v1/tasks/$first', {
        ...repeating,
        'title': 'Решаем логику',
        'task_version': 1,
        'scope': 'future',
      }, method: 'PUT');
      final newFirst = (edited['ids'] as List).first as String;
      await deliver('papa', newFirst);
      await titleOn([0, 1, 2, 3, 4, 5, 8], 'Решаем логику');
      await titleOn(
        [0, 1, 2, 3, 4, 5, 8],
        'Повторяем математику',
        present: false,
      );
      cases.add('edit_future_tasks');
      await mama.mutate('/v1/tasks/$newFirst/actions', {
        'action': 'stop_repeat',
      });
      await deliver('mama', newFirst);
      await titleOn([0, 1, 2, 3, 4, 5, 8], 'Решаем логику', present: false);
      await show(8);
      expect(find.text('Всё начинается с маленького шага!'), findsOneWidget);
      cases.add('stop_repeating_task');
      final lost =
          (await papa.mutate('/v1/schedules', {
                ...base,
                'title': 'Обновление без сигнала',
              }))['id']
              as String;
      expect(mama.rows('schedules'), isEmpty);
      final recovered = Completer<void>();
      fallback = Timer.periodic(const Duration(seconds: 3), (_) async {
        await Future.wait([mama.sync(), kid.sync()]);
        if (!recovered.isCompleted) recovered.complete();
      });
      await recovered.future.timeout(const Duration(seconds: 15));
      fallback.cancel();
      await titleOn([3, 4, 5, 6, 7, 8], 'Обновление без сигнала');
      cases.add('lost_signal_polling');
      await mama.mutate('/v1/schedules/$lost', {}, method: 'DELETE');
      await deliver('mama', lost);
      await titleOn(
        [3, 4, 5, 6, 7, 8],
        'Обновление без сигнала',
        present: false,
      );
      await show(5);
      await capture('event-cancelled');
      var detailTitle = 'Открытая карточка';
      final detailId =
          (await papa.mutate('/v1/schedules', {
                ...base,
                'title': detailTitle,
              }))['id']
              as String;
      await deliver('papa', detailId);
      for (final page in [3, 4, 5]) {
        await show(page);
        await revealField(tester, find.text(detailTitle));
        await tester.tap(find.text(detailTitle));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        final actor = page == 3 ? 'mama' : 'papa';
        detailTitle = 'Карточка обновлена $page';
        await clients[actor]!.mutate('/v1/schedules/$detailId/exceptions', {
          'date': date,
          'replacement': {
            ...base,
            'title': detailTitle,
            'start': '18:00',
            'end': '19:00',
            'place': 'Новое место',
          },
        });
        await deliver(actor, detailId);
        await tester.pumpAndSettle();
        Finder sheetText(String value) => find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(value),
        );
        expect(sheetText(detailTitle), findsOneWidget);
        expect(sheetText('18:00 — 19:00'), findsOneWidget);
        expect(sheetText('Новое место'), findsOneWidget);
        if (page == 5) await capture('details-updated');
        await clients[actor]!.mutate('/v1/schedules/$detailId/exceptions', {
          'date': date,
          'replacement': null,
        });
        await deliver(actor, detailId);
        await tester.pumpAndSettle();
        expect(
          sheetText('На этот день событие отменено или перенесено'),
          findsOneWidget,
        );
        expect(sheetText(detailTitle), findsNothing);
        if (page == 5) await capture('details-cancelled');
        await tester.tap(sheetText('Закрыть'));
        await tester.pumpAndSettle();
        await clients[actor]!.mutate('/v1/schedules/$detailId/exceptions', {
          'date': date,
          'replacement': {...base, 'title': detailTitle},
        });
        await deliver(actor, detailId);
      }
      cases.addAll([
        'open_event_details_update_all_clients',
        'open_event_details_cancel_all_clients',
      ]);
      await mama.mutate('/v1/schedules/$detailId', {}, method: 'DELETE');
      await deliver('mama', detailId);
      for (final entry in clients.entries) {
        expect(entry.value.sessionTag, identities[entry.key]);
        expect(entry.value.snapshot!['balance']['total'], 0);
        expect(entry.value.rows('ledger'), isEmpty);
        expect(
          entry.value.rows('tasks').every((t) => t['status'] == 'cancelled'),
          isTrue,
        );
        expect(calendarDay(entry.value.snapshot!, day), isEmpty);
        expect(calendarDay(entry.value.snapshot!, tomorrow), isEmpty);
      }
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'real_local_api': true,
        'independent_client_sessions': 3,
        'clients_restarted': false,
        'cases': cases,
        'screens': ['tasks', 'calendar', 'today', 'open_event_details'],
        'no_money_changes': true,
        'lost_push_polling_recovered': true,
        'physical_devices_tested': false,
        'fcm_transport_tested': false,
        'mobile_source_version': '0.1.35',
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
