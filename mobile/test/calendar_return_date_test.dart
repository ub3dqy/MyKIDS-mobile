import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';

import 'calendar_completion_date_test.dart'
    show CompletionFixture, CompletionFlow;
import 'calendar_keep_date_test.dart' show openCalendarApp, expectSelected;
import 'calendar_navigation_test.dart' show tapVisible;
import 'calendar_removal_date_test.dart' show chosenDay;
import 'field_layout_test.dart' show revealField;

const correction = 'Исправь второй шаг и пришли результат повторно';

enum ReturnRoute {
  tileDetails,
  listDetails,
  tileReview,
  listReview,
  todayReview;

  bool get list => this == listDetails || this == listReview;
  bool get review => this == tileReview || this == listReview;
}

class ReturnFixture extends CompletionFixture {
  final ReturnRoute route;
  int? failureStatus;

  ReturnFixture(DateTime selected, this.route, {String role = 'parent'})
    : super(
        selected,
        role == 'child'
            ? CompletionFlow.childTile
            : role == 'relative'
            ? CompletionFlow.relativeReview
            : CompletionFlow.parentInline,
      );

  String get failureMessage => failureStatus == 409
      ? 'Задание уже изменилось. Откройте его повторно'
      : 'Не удалось вернуть задание. Попробуйте ещё раз';

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
    // A refresh can replace the snapshot while the correction is being saved.
    snapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(snapshot)) as Map,
    );
    notifyListeners();
    await reply.future;
    if (closed) return {};
    if (failureStatus != null) {
      throw ApiFailure(failureStatus!, failureMessage);
    }
    task['status'] = 'returned';
    task['note'] = body['note'];
    task['version'] = 8;
    notifyListeners();
    return {'message': 'Задание возвращено на исправление'};
  }
}

Future<void> openReturn(
  WidgetTester tester,
  ReturnFixture repo,
  String view,
) async {
  await openCalendarApp(tester, repo);
  await tester.tap(find.widgetWithText(ChoiceChip, view));
  await tester.pumpAndSettle();
  if (repo.route == ReturnRoute.todayReview) {
    await tester.tap(find.text('Сегодня').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey('today-review-task')));
  } else {
    if (repo.route.list) {
      await tapVisible(tester, find.text('Семейные задания'));
    } else if (view == 'Месяц') {
      await tapVisible(
        tester,
        find.byWidgetPredicate(
          (w) => w is CalendarTile && w.entry.source?['id'] == 'task',
        ),
      );
    } else {
      await tapVisible(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label?.startsWith('Убрать игрушки,') ?? false),
        ),
      );
    }
    if (repo.route.review) {
      await tapVisible(tester, find.byKey(const ValueKey('review-task-task')));
    } else {
      await tapVisible(tester, find.text('Убрать игрушки'));
    }
  }
  await tapVisible(tester, find.text('Нужно исправить'));
  expect(find.text('Вернуть на исправление'), findsOneWidget);
  expect(find.byKey(const ValueKey('field-note')), findsOneWidget);
}

Future<void> saveReturn(WidgetTester tester, ReturnFixture repo) async {
  await tester.enterText(find.byKey(const ValueKey('field-note')), correction);
  await revealField(tester, find.text('Сохранить'));
  await tester.tap(find.text('Сохранить'));
  for (var i = 0; i < 12 && repo.attempts.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(repo.attempts, hasLength(1));
  expect(repo.attempts.single, {
    'path': '/v1/tasks/task/actions',
    'method': 'POST',
    'body': {'action': 'return', 'task_version': 7, 'note': correction},
    'offline': false,
  });
  if (repo.route != ReturnRoute.todayReview) {
    final calendar = tester.widget<CalendarScreen>(
      find.byType(CalendarScreen, skipOffstage: false),
    );
    expect(dateOnly(calendar.initialDay!), dateOnly(repo.selected));
  }
}

Future<void> backToCalendar(
  WidgetTester tester,
  ReturnFixture repo,
  String view,
) async {
  await tester.pumpAndSettle();
  expect(find.byType(FamilyForm), findsNothing);
  for (var i = 0; i < 2 && find.byType(BackButton).evaluate().isNotEmpty; i++) {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }
  expect(find.byType(BackButton), findsNothing);
  await tester.tap(find.text('Календарь').last);
  await tester.pumpAndSettle();
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

void expectReturned(ReturnFixture repo, Object? dueAt) {
  expect(repo.task['status'], 'returned');
  expect(repo.task['note'], correction);
  expect(repo.task['version'], 8);
  expect(repo.task['due_at'], dueAt);
  expect(repo.rows('tasks').last['id'], 'another-occurrence');
  expect(repo.rows('tasks').last['status'], 'assigned');
  expect(repo.rows('tasks').last['version'], 9);
  expect(repo.rows('tasks').last['note'], '');
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'morning:child': dateOnly(familyClock(null)),
    });
  });

  for (final role in ['parent', 'relative']) {
    for (final route in ReturnRoute.values) {
      for (final view in ['День', 'Неделя', 'Месяц']) {
        for (final offset in [-8, 8]) {
          testWidgets('$role $route $view return keeps selected date $offset', (
            tester,
          ) async {
            final repo = ReturnFixture(chosenDay(offset), route, role: role);
            final dueAt = repo.task['due_at'];
            await openReturn(tester, repo, view);
            await saveReturn(tester, repo);
            repo.reply.complete();
            await backToCalendar(tester, repo, view);
            expectReturned(repo, dueAt);
            expect(repo.attempts, hasLength(1));
          });
        }
      }
    }
  }

  for (final route in ReturnRoute.values) {
    for (final code in [409, 503]) {
      testWidgets('$route failed return $code and retry keep selected date', (
        tester,
      ) async {
        final repo = ReturnFixture(chosenDay(8), route)..failureStatus = code;
        final dueAt = repo.task['due_at'];
        await openReturn(tester, repo, 'Неделя');
        await saveReturn(tester, repo);
        repo.reply.complete();
        await tester.pumpAndSettle();
        expect(find.text(repo.failureMessage), findsOneWidget);
        expect(repo.task['status'], 'submitted');
        expect(repo.task['version'], 7);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('field-note')))
              .controller!
              .text,
          correction,
        );
        repo.failureStatus = null;
        await tapVisible(tester, find.text('Сохранить'));
        await backToCalendar(tester, repo, 'Неделя');
        expectReturned(repo, dueAt);
        expect(repo.attempts, hasLength(2));
        expect(repo.attempts.last, repo.attempts.first);
      });
    }

    testWidgets('$route cancelled return keeps selected date', (tester) async {
      final repo = ReturnFixture(chosenDay(-8), route);
      await openReturn(tester, repo, 'Месяц');
      await tester.enterText(
        find.byKey(const ValueKey('field-note')),
        correction,
      );
      await tester.tap(find.byType(BackButton));
      await backToCalendar(tester, repo, 'Месяц');
      expect(repo.attempts, isEmpty);
      expect(repo.task['status'], 'submitted');
      expect(repo.task['version'], 7);
    });

    testWidgets('$route missing correction preserves form and calendar date', (
      tester,
    ) async {
      final repo = ReturnFixture(chosenDay(8), route);
      final dueAt = repo.task['due_at'];
      await openReturn(tester, repo, 'День');
      await tapVisible(tester, find.text('Сохранить'));
      expect(find.text('Заполните поле «Что нужно исправить»'), findsOneWidget);
      expect(repo.attempts, isEmpty);
      await saveReturn(tester, repo);
      repo.reply.complete();
      await backToCalendar(tester, repo, 'День');
      expectReturned(repo, dueAt);
    });
  }

  for (final view in ['День', 'Неделя', 'Месяц']) {
    for (final offset in [-8, 8]) {
      testWidgets('child $view remote return keeps selected date $offset', (
        tester,
      ) async {
        final repo = ReturnFixture(
          chosenDay(offset),
          ReturnRoute.tileDetails,
          role: 'child',
        );
        repo.task['status'] = 'submitted';
        repo.snapshot!['submissions'] = [repo.submission];
        await openCalendarApp(tester, repo);
        await tester.tap(find.widgetWithText(ChoiceChip, view));
        await tester.pumpAndSettle();
        repo.snapshot = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(repo.snapshot)) as Map,
        );
        final dueAt = repo.task['due_at'];
        repo.task.addAll({
          'status': 'returned',
          'note': correction,
          'version': 8,
        });
        repo.notifyListeners();
        await backToCalendar(tester, repo, view);
        expectReturned(repo, dueAt);
        expect(repo.attempts, isEmpty);
      });
    }
  }
}
