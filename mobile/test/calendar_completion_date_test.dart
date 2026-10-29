import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/task_rewards.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar_keep_date_test.dart'
    show KeepDateFixture, openCalendarApp, expectSelected;
import 'calendar_navigation_test.dart' show tapVisible;
import 'calendar_removal_date_test.dart' show chosenDay;
import 'field_layout_test.dart' show revealField;

enum CompletionFlow {
  childTile,
  childTasks,
  childResults,
  parentInline,
  parentReview,
  parentResults,
  relativeReview,
  parentCountReview,
  parentCountResults;

  bool get child => index <= childResults.index;
  bool get results =>
      this == childResults ||
      this == parentResults ||
      this == parentCountResults;
  bool get counted => this == parentCountReview || this == parentCountResults;
  bool get review =>
      this == parentReview ||
      this == relativeReview ||
      this == parentCountReview;
  String get role => child
      ? 'child'
      : this == relativeReview
      ? 'relative'
      : 'parent';
}

class CompletionFixture extends KeepDateFixture {
  final CompletionFlow flow;
  final attempts = <Map<String, dynamic>>[];
  final reply = Completer<void>();
  bool reject = false, closed = false;

  CompletionFixture(super.selected, this.flow) : super(userRole: flow.role) {
    snapshot!['schedules'] = [];
    snapshot!['user']['id'] = flow.role;
    snapshot!['balance'] = {'total': 0, 'reserved': 0, 'available': 0};
    snapshot!['ledger'] = <Map<String, dynamic>>[];
    task.addAll({
      'status': flow.child ? 'assigned' : 'submitted',
      'reviewer_id': flow.role == 'relative' ? 'relative' : null,
      'is_required': 0,
      'reward': flow.counted ? 50 : 30,
      'penalty': 0,
      'require_photo': 0,
      'recurrence_id': 'daily',
      'occurrence_date': dateOnly(selected),
      'planned_start': tz.TZDateTime(
        familyClock(snapshot).location,
        selected.year,
        selected.month,
        selected.day,
        9,
      ).toUtc().toIso8601String(),
      'planned_end': tz.TZDateTime(
        familyClock(snapshot).location,
        selected.year,
        selected.month,
        selected.day,
        9,
        30,
      ).toUtc().toIso8601String(),
      if (flow.counted) 'reward_options': mathRewardExample(),
    });
    snapshot!['submissions'] = [if (!flow.child) submission];
    final next = tz.TZDateTime(
      familyClock(snapshot).location,
      selected.year,
      selected.month,
      selected.day + 1,
      17,
    );
    (snapshot!['tasks'] as List).add({
      ...task,
      'id': 'another-occurrence',
      'title': 'Задание на другую дату',
      'version': 9,
      'status': 'assigned',
      'due_at': next.toUtc().toIso8601String(),
      'occurrence_date': dateOnly(next),
      'planned_start': null,
      'planned_end': null,
    });
  }

  Map<String, dynamic> get task =>
      (snapshot!['tasks'] as List).first as Map<String, dynamic>;

  Map<String, dynamic> get submission => {
    'id': 'result',
    'task_id': 'task',
    'note': 'Работа выполнена',
    'accepted': 1,
    'attachment_ids': '[]',
    'marked_at': task['due_at'],
    'received_at': task['due_at'],
  };

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
      'body': Map<String, dynamic>.from(body),
      'method': method,
      'offline': offlineSubmission,
    });
    // A foreground refresh replaces the snapshot before the action finishes.
    snapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(snapshot)) as Map,
    );
    notifyListeners();
    await reply.future;
    if (closed) return {};
    if (reject) {
      throw ApiFailure(409, 'Результат изменился, повторите проверку');
    }
    if (!online) {
      if (!offlineSubmission) {
        throw ApiFailure(503, 'Нет связи');
      }
      return {'queued': true, 'message': 'Сохранено для отправки'};
    }
    task['status'] = flow.child ? 'submitted' : 'completed';
    task['version'] = 8;
    if (flow.child) {
      snapshot!['submissions'] = [submission];
    } else {
      task['awarded_reward'] = flow.counted ? 25 : 30;
      if (flow.counted) task['completed_count'] = body['completed_count'];
    }
    notifyListeners();
    return {'accepted': true, 'message': 'Результат сохранён'};
  }

  @override
  void dispose() {
    closed = true;
    if (!reply.isCompleted) reply.complete();
    super.dispose();
  }
}

Future<void> openCompletion(
  WidgetTester tester,
  CompletionFixture repo,
  String view,
) async {
  await openCalendarApp(tester, repo);
  await tester.tap(find.widgetWithText(ChoiceChip, view));
  await tester.pumpAndSettle();
  if (repo.flow.results) {
    await tapVisible(tester, find.text('Предметы и оценки'));
    expect(
      find.byKey(ValueKey('calendar-results-list-${dateOnly(repo.selected)}')),
      findsOneWidget,
    );
    final action = find.byKey(
      ValueKey('result-${repo.flow.child ? 'submit' : 'complete'}-task'),
    );
    await revealField(tester, action);
    await tester.tap(action);
    if (!repo.flow.child) await tester.pumpAndSettle();
    return;
  }
  if (repo.flow == CompletionFlow.childTasks ||
      repo.flow == CompletionFlow.parentReview) {
    await tapVisible(tester, find.text('Семейные задания'));
  } else if (view == 'Месяц') {
    await tapVisible(
      tester,
      find.byWidgetPredicate(
        (w) => w is CalendarTile && w.entry.source?['id'] == 'task',
      ),
    );
  } else {
    final tile = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('Убрать игрушки,') ?? false),
    );
    await tapVisible(tester, tile);
  }
  if (repo.flow.child) {
    await tapVisible(tester, find.text('Готово — отправить на проверку'));
  } else {
    if (repo.flow.review) {
      await tapVisible(tester, find.byKey(const ValueKey('review-task-task')));
      expect(find.text('Результат: Работа выполнена'), findsWidgets);
    } else {
      await tapVisible(tester, find.text('Убрать игрушки'));
    }
    final action = find.text('Подтвердить выполнение');
    await revealField(tester, action);
    await tester.tap(action);
    if (repo.flow.counted) await tester.pumpAndSettle();
  }
}

Future<void> startCompletion(
  WidgetTester tester,
  CompletionFixture repo,
) async {
  final flow = repo.flow;
  if (flow.counted) {
    await tester.enterText(
      find.byKey(const ValueKey('task-completed-count')),
      '5',
    );
  }
  if (flow != CompletionFlow.childResults &&
      flow != CompletionFlow.parentInline &&
      flow != CompletionFlow.parentReview &&
      flow != CompletionFlow.relativeReview) {
    final label = flow.counted
        ? 'Подтвердить результат'
        : flow.child
        ? 'Отправить на проверку'
        : 'Выполнено';
    await revealField(tester, find.text(label));
    await tester.tap(find.text(label));
  }
  // The action stays pending while the app and all open routes rebuild.
  for (var i = 0; i < 12 && repo.attempts.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(repo.attempts, hasLength(1));
  final request = repo.attempts.single;
  final body = request['body'] as Map;
  expect(request['method'], 'POST');
  expect(
    request['path'],
    '/v1/tasks/task/${flow.child ? 'submissions' : 'actions'}',
  );
  expect(body['task_version'], 7);
  if (flow.child) {
    expect(request['offline'], isTrue);
    expect(DateTime.tryParse(body['marked_at'] as String), isNotNull);
  } else {
    expect(body['action'], flow.results ? 'complete' : 'approve');
    if (flow.results) expect(body['date'], dateOnly(repo.selected));
    if (flow.counted) expect(body['completed_count'], 5);
  }
  final calendar = tester.widget<CalendarScreen>(
    find.byType(CalendarScreen, skipOffstage: false),
  );
  expect(dateOnly(calendar.initialDay!), dateOnly(repo.selected));
}

Future<void> backToSelection(
  WidgetTester tester,
  CompletionFixture repo,
  String view,
) async {
  await tester.pumpAndSettle();
  if (find.text('Здорово!').evaluate().isNotEmpty) {
    await tester.tap(find.text('Здорово!'));
    await tester.pumpAndSettle();
  }
  if (repo.flow.results) {
    expect(
      find.byKey(ValueKey('calendar-results-list-${dateOnly(repo.selected)}')),
      findsOneWidget,
    );
  }
  // The review route can sit above a dated task list or a single task route.
  for (var i = 0; i < 2 && find.byType(BackButton).evaluate().isNotEmpty; i++) {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }
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
  await tester.tap(find.text('Задания').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Календарь').last);
  await tester.pumpAndSettle();
  await expectSelected(tester, repo.selected, view);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'morning:child': dateOnly(familyClock(null)),
    });
  });

  for (final view in ['День', 'Неделя', 'Месяц']) {
    for (final flow in CompletionFlow.values) {
      for (final offset in [-8, 8]) {
        testWidgets('$view $flow retains date $offset after completion', (
          tester,
        ) async {
          final repo = CompletionFixture(chosenDay(offset), flow);
          await openCompletion(tester, repo, view);
          await startCompletion(tester, repo);
          repo.reply.complete();
          await backToSelection(tester, repo, view);
          expect(repo.task['status'], flow.child ? 'submitted' : 'completed');
          expect(repo.rows('tasks').last['status'], 'assigned');
          expect(repo.rows('tasks').last['version'], 9);
          expect(repo.attempts, hasLength(1));
        });
      }
    }
  }

  for (final flow in CompletionFlow.values) {
    testWidgets('$flow action conflict retains selected date', (tester) async {
      final repo = CompletionFixture(chosenDay(8), flow)..reject = true;
      await openCompletion(tester, repo, 'Неделя');
      await startCompletion(tester, repo);
      repo.reply.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Результат изменился, повторите проверку'),
        findsOneWidget,
      );
      expect(repo.task['version'], 7);
      await backToSelection(tester, repo, 'Неделя');
    });
  }

  for (final flow in [
    CompletionFlow.childTile,
    CompletionFlow.parentCountReview,
    CompletionFlow.parentResults,
  ]) {
    for (final offset in [-8, 8]) {
      testWidgets('$flow declined confirmation retains date $offset', (
        tester,
      ) async {
        final repo = CompletionFixture(chosenDay(offset), flow);
        await openCompletion(tester, repo, 'Месяц');
        await tester.tap(find.text('Отмена'));
        await backToSelection(tester, repo, 'Месяц');
        expect(repo.attempts, isEmpty);
        expect(repo.task['version'], 7);
      });
    }
  }

  for (final flow in [
    CompletionFlow.childTile,
    CompletionFlow.childTasks,
    CompletionFlow.childResults,
  ]) {
    testWidgets('$flow offline submission retains selected date', (
      tester,
    ) async {
      final repo = CompletionFixture(chosenDay(-8), flow)..online = false;
      await openCompletion(tester, repo, 'Неделя');
      await startCompletion(tester, repo);
      repo.reply.complete();
      await backToSelection(tester, repo, 'Неделя');
      expect(repo.task['status'], 'assigned');
    });
  }

  for (final view in ['День', 'Неделя', 'Месяц']) {
    for (final coins in [0, 30]) {
      testWidgets('$view remote approval with $coins coins retains date', (
        tester,
      ) async {
        final repo = CompletionFixture(chosenDay(-8), CompletionFlow.childTile);
        repo.task['status'] = 'submitted';
        repo.snapshot!['submissions'] = [repo.submission];
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await openCalendarApp(tester, repo);
        await tester.tap(find.widgetWithText(ChoiceChip, view));
        await tester.pumpAndSettle();
        repo.task['status'] = 'completed';
        repo.task['version'] = 8;
        repo.task['awarded_reward'] = coins;
        repo.snapshot!['balance'] = {
          'total': coins,
          'reserved': 0,
          'available': coins,
        };
        repo.snapshot!['ledger'] = [
          {
            'id': 'approved-task',
            'child_id': 'child',
            'source_type': 'task',
            'actual': coins,
          },
        ];
        repo.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('Твои старания заметили!'), findsOneWidget);
        await backToSelection(tester, repo, view);
        expect(repo.attempts, isEmpty);
      });
    }
  }
}
