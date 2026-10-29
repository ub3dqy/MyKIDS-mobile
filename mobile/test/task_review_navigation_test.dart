import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';

import 'task_time_labels_test.dart' show TaskTimeFixture;
import 'field_layout_test.dart' show revealField;

TaskTimeFixture reviewFixture({String role = 'parent'}) {
  final repo = TaskTimeFixture(role: role);
  (repo.snapshot!['tasks'] as List).first['status'] = 'submitted';
  (repo.snapshot!['tasks'] as List).last['status'] = 'completed';
  repo.snapshot!['submissions'] = [
    {
      'task_id': 'evening',
      'note': 'Вечером всё сделано',
      'marked_at': '2026-10-13T20:15:00Z',
      'received_at': '2026-10-13T20:15:01Z',
      'attachment_ids': '[]',
      'accepted': 1,
    },
  ];
  return repo;
}

void main() {
  testWidgets(
    'Today names the submitted evening occurrence and opens its result without approval',
    (tester) async {
      final repo = reviewFixture();
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(false),
          home: Builder(
            builder: (context) => Scaffold(
              body: TodayScreen(
                repository: repo,
                openPage: (_) => fail('Must open the particular result'),
                onReviewTask: (id) =>
                    openTaskReview(context, repo, (action) async {
                      await action();
                    }, id),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('today-review-evening'));
      await tester.ensureVisible(review);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('today-review-card-evening')),
          matching: find.text(repo.eveningLabel),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today-review-morning')), findsNothing);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.text('Проверка задания'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-evening')), findsOneWidget);
      expect(find.byKey(const ValueKey('task-morning')), findsNothing);
      expect(find.text('Результат: Вечером всё сделано'), findsOneWidget);
      expect(find.text('Подтвердить выполнение'), findsOneWidget);
      expect(repo.mutations, isEmpty);
    },
  );

  testWidgets(
    'Collapsed submitted task has a direct review button at large text size',
    (tester) async {
      final repo = reviewFixture();
      tester.view.physicalSize = const Size(320, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: TaskScreen(
              repository: repo,
              perform: (action) async {
                await action();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('review-task-evening'));
      await revealField(tester, review);
      await tester.pumpAndSettle();
      expect(find.text('Ждёт проверки'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-task-morning')), findsNothing);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.text('Результат: Вечером всё сделано'), findsOneWidget);
      expect(repo.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Review of a previous-day occurrence bypasses the current-day filter',
    (tester) async {
      final repo = reviewFixture();
      (repo.snapshot!['tasks'] as List).first['due_at'] =
          '2026-10-01T23:00:00+03:00';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskScreen(
              repository: repo,
              reviewTaskId: 'evening',
              perform: (action) async {
                await action();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-evening')), findsOneWidget);
      expect(find.text('Результат: Вечером всё сделано'), findsOneWidget);
      expect(
        find.text('Повторяющиеся задания на выбранный день'),
        findsNothing,
      );
    },
  );

  for (final role in ['child', 'relative']) {
    testWidgets('$role cannot open an unauthorized review result', (
      tester,
    ) async {
      final repo = reviewFixture(role: role);
      repo.snapshot!['user']['id'] = 'someone-else';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskScreen(
              repository: repo,
              reviewTaskId: 'evening',
              perform: (action) async {
                await action();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Задание больше недоступно для проверки.'),
        findsOneWidget,
      );
      expect(find.text('Подтвердить выполнение'), findsNothing);
      expect(repo.mutations, isEmpty);
    });
  }
}
