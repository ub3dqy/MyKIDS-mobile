import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/task_rules.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';

import 'field_layout_test.dart' show revealField;
import 'task_time_labels_test.dart' show TaskTimeFixture;

TaskTimeFixture morningFixture() {
  final repo = TaskTimeFixture();
  final task = repo.rows('tasks').last;
  final now = DateTime.now().toUtc();
  repo.snapshot!['tasks'] = [
    {
      ...task,
      'status': 'submitted',
      'planned_start': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'planned_end': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'due_at': now.add(const Duration(hours: 6)).toIso8601String(),
    },
  ];
  repo.snapshot!['submissions'] = [
    {
      'task_id': 'morning',
      'accepted': 1,
      'note': 'Утренняя отметка',
      'marked_at': now.toIso8601String(),
      'received_at': now.toIso8601String(),
      'attachment_ids': '[]',
    },
  ];
  return repo;
}

void main() {
  test('adult completion decision uses the planned end, not the reporting deadline', () {
    final repo = morningFixture();
    addTearDown(repo.client.close);
    addTearDown(repo.dispose);
    final task = repo.rows('tasks').single;
    expect(canMarkTaskNotCompleted(repo.snapshot!['user'], task), isTrue);
    expect(canMarkTaskNotCompleted({'role': 'child'}, task), isFalse);
    expect(
      canMarkTaskNotCompleted(repo.snapshot!['user'], {
        ...task,
        'status': 'not_completed',
      }),
      isFalse,
    );
    expect(
      canMarkTaskNotCompleted(repo.snapshot!['user'], {
        ...task,
        'planned_end': null,
      }),
      isFalse,
    );
    expect(
      canMarkTaskNotCompleted(repo.snapshot!['user'], {
        ...task,
        'planned_end': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      }),
      isFalse,
    );
  });

  testWidgets(
    'Today result can be rejected before reporting deadline without opening details; stale approval stays blocked',
    (tester) async {
      final repo = morningFixture();
      addTearDown(repo.client.close);
      addTearDown(repo.dispose);
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: AnimatedBuilder(
                animation: repo,
                builder: (_, _) => TodayScreen(
                  repository: repo,
                  openPage: (_) => fail('Open this exact occurrence'),
                  onReviewTask: (id) =>
                      openTaskReview(context, repo, (operation) async {
                        await operation();
                      }, id),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('today-review-morning'));
      await revealField(tester, review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      final approve = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить выполнение'),
          )
          .onPressed!;
      final failure = find.byKey(const ValueKey('task-not-completed-morning'));
      expect(failure, findsOneWidget);
      expect(find.text('Скрыть подробности'), findsNothing);
      await revealField(tester, failure);
      await tester.tap(failure);
      await tester.pumpAndSettle();
      expect(find.textContaining('В календаре:'), findsOneWidget);
      final date = find.text(
        taskCalendarTimeText(repo.snapshot, repo.rows('tasks').single)!,
      );
      expect(tester.getTopLeft(date).dy, greaterThanOrEqualTo(0));
      expect(tester.getBottomLeft(date).dy, lessThanOrEqualTo(760));
      expect(find.text('Штраф: 500 монет'), findsOneWidget);
      final charge = find.widgetWithText(FilledButton, 'Списать 500 монет');
      expect(charge.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(charge).dy, lessThanOrEqualTo(760));
      expect(repo.mutations, isEmpty);
      await tester.tap(charge);
      await tester.pumpAndSettle();
      expect(repo.rows('tasks').single['status'], 'not_completed');
      expect(repo.mutations.single['action'], 'not_completed');
      expect(repo.mutations.single['task_version'], 7);
      expect(find.text('Подтвердить выполнение'), findsNothing);
      approve();
      await tester.pumpAndSettle();
      expect(repo.mutations, hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today-review-morning')), findsNothing);
      expect(find.text('Результатов на проверке: 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a planned task keeps the later child reporting deadline visible in details',
    (tester) async {
      final repo = morningFixture();
      addTearDown(repo.client.close);
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskScreen(
              repository: repo,
              reviewTaskId: 'morning',
              perform: (operation) async {
                await operation();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Подробнее'));
      await tester.tap(find.text('Подробнее'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Отметить в приложении до:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
