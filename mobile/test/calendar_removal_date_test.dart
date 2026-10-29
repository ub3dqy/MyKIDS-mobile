import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar_keep_date_test.dart'
    show KeepDateFixture, openCalendarApp, expectSelected;
import 'calendar_navigation_test.dart' show tapVisible;
import 'field_layout_test.dart' show revealField;

enum Removal {
  task,
  taskDay,
  taskRepeat,
  event,
  eventRepeat,
  eventDay;

  bool get isTask => index <= taskRepeat.index;
  bool get taskForm => this == task || this == taskDay;
  bool get recurring => this != task && this != event;
  String get actionLabel => switch (this) {
    task || taskDay => 'Отменить',
    taskRepeat => 'Остановить повторение',
    event => 'Удалить событие',
    eventRepeat => 'Удалить событие и повторения',
    eventDay => 'Отменить только этот день',
  };
  String get confirmLabel => taskForm
      ? 'Сохранить'
      : this == taskRepeat
      ? 'Остановить повтор'
      : 'Подтвердить';
}

class RemovalFixture extends KeepDateFixture {
  final Removal removal;
  final attempts = <Map<String, dynamic>>[];
  final reply = Completer<void>();
  bool reject = false, closed = false;

  List<Map<String, dynamic>> data(String name) =>
      (snapshot![name] as List).cast<Map<String, dynamic>>();

  RemovalFixture(super.selected, this.removal) {
    final clock = familyClock(snapshot);
    snapshot!['tasks'] = removal.isTask ? snapshot!['tasks'] : [];
    snapshot!['schedules'] = removal.isTask ? [] : snapshot!['schedules'];
    if (removal.isTask) {
      final task = data('tasks').single;
      task['planned_start'] = tz.TZDateTime(
        clock.location,
        selected.year,
        selected.month,
        selected.day,
        9,
      ).toUtc().toIso8601String();
      task['planned_end'] = tz.TZDateTime(
        clock.location,
        selected.year,
        selected.month,
        selected.day,
        9,
        30,
      ).toUtc().toIso8601String();
      task['occurrence_date'] = dateOnly(selected);
      if (removal.recurring) {
        task['recurrence_id'] = 'daily';
        snapshot!['task_recurrences'] = [
          {
            'id': 'daily',
            'active': 1,
            'weekdays': '[1,2,3,4,5,6,7]',
            'until': null,
          },
        ];
        final next = tz.TZDateTime(
          clock.location,
          clock.year,
          clock.month,
          clock.day + 20,
          20,
        );
        (snapshot!['tasks'] as List).add({
          ...task,
          'id': 'next-task',
          'due_at': next.toUtc().toIso8601String(),
          'planned_start': null,
          'planned_end': null,
          'occurrence_date': dateOnly(next),
        });
      }
    } else if (removal.recurring) {
      data('schedules').single
          .addAll({'date': null, 'weekdays': '[1,2,3,4,5,6,7]'});
    }
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    attempts.add({
      'path': path,
      'method': method,
      'body': Map<String, dynamic>.from(body),
      'offline': offlineSubmission,
    });
    // An ordinary foreground refresh can finish while the mutation is pending.
    snapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(snapshot)) as Map,
    );
    notifyListeners();
    await reply.future;
    if (closed) return {};
    if (reject) throw ApiFailure(503, 'Проверочное действие не выполнено');
    if (!online) {
      if (!offlineSubmission) {
        throw ApiFailure(503, 'Для этого действия нужен интернет');
      }
      return {
        'queued': true,
        'message': 'Сохранено. Отправим после подключения',
      };
    }
    if (removal.isTask) {
      final task = data('tasks').firstWhere((row) => row['id'] == 'task');
      if (body['action'] == 'stop_repeat') {
        data('task_recurrences').single['active'] = 0;
        final today = dateOnly(familyClock(snapshot));
        for (final row in data('tasks')) {
          if ((row['occurrence_date'] as String).compareTo(today) >= 0) {
            row['status'] = 'cancelled';
          }
        }
      } else {
        task['status'] = 'cancelled';
      }
    } else if (method == 'DELETE') {
      data('schedules').single['active'] = 0;
    } else {
      (snapshot!['schedule_exceptions'] as List).add({
        'schedule_id': data('schedules').single['id'],
        'date': body['date'],
        'replacement': null,
      });
    }
    notifyListeners();
    return {'message': 'Сохранено'};
  }

  @override
  void dispose() {
    closed = true;
    if (!reply.isCompleted) reply.complete();
    super.dispose();
  }
}

DateTime chosenDay(int offset) {
  final now = familyClock({
    'family': {'timezone': 'Europe/Moscow'},
  });
  return tz.TZDateTime(now.location, now.year, now.month, now.day + offset);
}

Future<void> openRemoval(
  WidgetTester tester,
  RemovalFixture repo,
  String view,
) async {
  await openCalendarApp(tester, repo);
  await tester.tap(find.widgetWithText(ChoiceChip, view));
  await tester.pumpAndSettle();
  if (repo.removal == Removal.task) {
    await tapVisible(tester, find.text('Семейные задания'));
  } else if (view == 'Месяц') {
    await tapVisible(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is CalendarTile &&
            w.entry.source?['id'] ==
                (repo.removal.isTask ? 'task' : 'Событие для изменения'),
      ),
    );
  } else {
    final title = repo.removal.isTask
        ? 'Убрать игрушки'
        : 'Событие для изменения';
    final tile = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('$title,') ?? false),
    );
    final column = find
        .ancestor(
          of: find.byKey(
            ValueKey('calendar-day-end-${dateOnly(repo.selected)}'),
          ),
          matching: find.byType(SizedBox),
        )
        .first;
    await tapVisible(
      tester,
      view == 'Неделя' ? find.descendant(of: column, matching: tile) : tile,
    );
  }
  if (repo.removal.isTask) {
    await tapVisible(tester, find.text('Убрать игрушки'));
  }
  await tapVisible(tester, find.text(repo.removal.actionLabel));
}

Future<void> expectCalendar(
  WidgetTester tester,
  RemovalFixture repo,
  String view,
) async {
  await tester.drag(
    find
        .descendant(
          of: find.byType(CalendarScreen),
          matching: find.byType(Scrollable),
        )
        .first,
    const Offset(0, 10000),
  );
  await tester.pumpAndSettle();
  await expectSelected(tester, repo.selected, view);
}

Future<void> startRemoval(WidgetTester tester, RemovalFixture repo) async {
  final button = find.text(repo.removal.confirmLabel);
  await revealField(tester, button);
  await tester.tap(button);
  // Wait for the decision route to finish closing without settling the pending request spinner.
  for (var i = 0; i < 12 && repo.attempts.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(repo.attempts, hasLength(1));
  final calendar = tester.widget<CalendarScreen>(
    find.byType(CalendarScreen, skipOffstage: false),
  );
  expect(dateOnly(calendar.initialDay!), dateOnly(repo.selected));
}

Future<void> returnToCalendar(
  WidgetTester tester,
  RemovalFixture repo, {
  bool taskFormOpen = false,
}) async {
  if (taskFormOpen) {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }
  if (repo.removal.isTask) {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }
}

void expectRequest(RemovalFixture repo) {
  final request = repo.attempts.single;
  final body = request['body'] as Map;
  expect(
    request['path'],
    repo.removal.isTask
        ? '/v1/tasks/task/actions'
        : '/v1/schedules/Событие для изменения${repo.removal == Removal.eventDay ? '/exceptions' : ''}',
  );
  if (repo.removal.isTask) {
    expect(
      body['action'],
      repo.removal == Removal.taskRepeat ? 'stop_repeat' : 'cancel',
    );
    expect(body['task_version'], 7);
  } else {
    expect(body['expected_revision'], 1);
    expect(
      request['method'],
      repo.removal == Removal.eventDay ? 'POST' : 'DELETE',
    );
    if (repo.removal == Removal.eventDay) {
      expect(body['date'], dateOnly(repo.selected));
    }
  }
}

void main() {
  for (final view in ['День', 'Неделя', 'Месяц']) {
    for (final removal in Removal.values) {
      for (final offset in [-8, 8]) {
        testWidgets(
          '$view $removal retains selected date $offset after removal and section return',
          (tester) async {
            final repo = RemovalFixture(chosenDay(offset), removal);
            await openRemoval(tester, repo, view);
            await startRemoval(tester, repo);
            expectRequest(repo);
            repo.reply.complete();
            await tester.pumpAndSettle();
            await returnToCalendar(tester, repo);
            await expectCalendar(tester, repo, view);
            final keptPastTask = removal == Removal.taskRepeat && offset < 0;
            expect(
              calendarDay(repo.snapshot!, repo.selected).isEmpty,
              !keptPastTask,
            );
            if (removal == Removal.eventDay) {
              final day = repo.selected;
              expect(
                calendarDay(
                  repo.snapshot!,
                  DateTime(day.year, day.month, day.day + 1, 12),
                ),
                isNotEmpty,
              );
            }
            if (removal == Removal.taskDay) {
              expect(
                repo
                    .rows('tasks')
                    .firstWhere((row) => row['id'] == 'next-task')['status'],
                'assigned',
              );
            }
            await tester.tap(find.text('Задания').last);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Календарь').last);
            await tester.pumpAndSettle();
            await expectCalendar(tester, repo, view);
          },
        );
      }
    }
  }

  for (final removal in Removal.values) {
    testWidgets('$removal declining confirmation preserves calendar date', (
      tester,
    ) async {
      final repo = RemovalFixture(chosenDay(-8), removal);
      await openRemoval(tester, repo, 'Неделя');
      if (removal.taskForm) {
        await tester.tap(find.byType(BackButton));
      } else {
        await tester.tap(
          find.text(removal == Removal.taskRepeat ? 'Вернуться' : 'Назад'),
        );
      }
      await tester.pumpAndSettle();
      await returnToCalendar(tester, repo);
      await expectCalendar(tester, repo, 'Неделя');
      expect(repo.attempts, isEmpty);
      expect(calendarDay(repo.snapshot!, repo.selected), isNotEmpty);
    });

    testWidgets('$removal failed removal preserves calendar date', (
      tester,
    ) async {
      final repo = RemovalFixture(chosenDay(8), removal)..reject = true;
      await openRemoval(tester, repo, 'Месяц');
      await startRemoval(tester, repo);
      repo.reply.complete();
      await tester.pumpAndSettle();
      expect(find.text('Проверочное действие не выполнено'), findsOneWidget);
      await returnToCalendar(tester, repo, taskFormOpen: removal.taskForm);
      await expectCalendar(tester, repo, 'Месяц');
      expect(calendarDay(repo.snapshot!, repo.selected), isNotEmpty);
    });
  }

  for (final removal in [
    Removal.event,
    Removal.eventRepeat,
    Removal.eventDay,
  ]) {
    testWidgets('$removal queued offline preserves calendar date', (
      tester,
    ) async {
      final repo = RemovalFixture(chosenDay(-8), removal)..online = false;
      await openRemoval(tester, repo, 'Неделя');
      await startRemoval(tester, repo);
      expect(repo.attempts.single['offline'], isTrue);
      repo.reply.complete();
      await tester.pumpAndSettle();
      await expectCalendar(tester, repo, 'Неделя');
      expect(calendarDay(repo.snapshot!, repo.selected), isNotEmpty);
    });
  }
}
