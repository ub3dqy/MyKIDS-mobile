import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/school_screen.dart';
import 'package:mykids_family/task_repeat.dart';
import 'package:mykids_family/task_rewards.dart';
import 'package:mykids_family/task_rules.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'field_layout_test.dart' show mountFields, revealField;
import 'support/calendar_results_fixture.dart';
import 'task_edit_test.dart' show TaskEditFixture;
import 'task_rules_test.dart' show showTasks, reveal;

class ResultRewardFixture extends TaskEditFixture {
  ResultRewardFixture({
    String role = 'parent',
    String status = 'submitted',
    bool graded = true,
  }) : super(userRole: role, withTask: true) {
    task.addAll({
      'title': 'Математика: шесть задач',
      'status': status,
      'due_at': DateTime.now().toUtc().toIso8601String(),
      'reward': graded ? 50 : 30,
      'penalty': 0,
      'is_required': 0,
      'reward_options': graded ? mathRewardExample() : null,
    });
  }
  Map<String, dynamic> get task =>
      (snapshot!['tasks'] as List).first as Map<String, dynamic>;
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test(
    'the math rule awards one amount and displays a zero result honestly',
    () {
      final options = mathRewardExample();
      expect(
        [
          for (var count = 0; count <= 6; count++)
            taskRewardForCount(options, count),
        ],
        [0, 0, 0, 0, 0, 25, 50],
      );
      expect(
        taskRewardRulesText(options),
        '6 из 6 — 50 монет\n5 из 6 — 25 монет\nМеньше 5 — 0 монет',
      );
      final task = {
        'status': 'completed',
        'reward': 50,
        'reward_options': options,
        'completed_count': 4,
        'awarded_reward': 0,
      };
      expect(taskTermsText(task), contains('без начисления монет'));
      expect(taskTermsText(task), isNot(contains('50 монет')));
      expect(
        rewardOptionsError({
          'total': 6,
          'tiers': [
            {'minimum': 6, 'coins': 10},
            {'minimum': 5, 'coins': 25},
          ],
        }),
        isNotNull,
      );
      expect(
        rewardOptionsError({
          'total': 6,
          'tiers': [
            {'minimum': 5, 'coins': 25},
            {'minimum': 5, 'coins': 10},
          ],
        }),
        isNotNull,
      );
    },
  );

  testWidgets(
    'parent can edit a fixed reward into configurable result tiers and two required photos',
    (tester) async {
      final repo = ResultRewardFixture(status: 'assigned', graded: false);
      await showTasks(tester, repo);
      await tester.tap(find.text('Ждут внимания'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Математика: шесть задач'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Редактировать задание'));
      await tester.tap(find.text('Редактировать задание'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('field-reward_type')));
      await tester.tap(find.byKey(const ValueKey('field-reward_type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('По числу решённых задач').last);
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('reward-coins-1')));
      await tester.enterText(
        find.byKey(const ValueKey('reward-coins-1')),
        '25',
      );
      await reveal(tester, find.text('Нужна фотография результата'));
      await tester.tap(find.text('Нужна фотография результата'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('field-required_photos')));
      await tester.enterText(
        find.byKey(const ValueKey('field-required_photos')),
        '2',
      );
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['reward_options'], mathRewardExample());
      expect(repo.mutations.single['reward'], 50);
      expect(repo.mutations.single['required_photos'], 2);
      expect(repo.mutations.single.containsKey('reward_type'), isFalse);
      expect(find.byType(FamilyForm), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    },
  );

  for (final count in [6, 5, 4]) {
    testWidgets(
      'review requires an explicit count and previews the award for $count correct tasks',
      (tester) async {
        final repo = ResultRewardFixture();
        await mountFields(
          tester,
          Scaffold(
            body: TaskScreen(
              repository: repo,
              reviewTaskId: 'task',
              perform: (action) async {
                await action();
              },
            ),
          ),
          scale: 1.6,
        );
        await revealField(tester, find.text('Подтвердить выполнение'));
        await tester.tap(find.text('Подтвердить выполнение'));
        await tester.pumpAndSettle();
        expect(repo.mutations, isEmpty);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Подтвердить результат'),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const ValueKey('task-completed-count')),
          count.toString(),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Начислить: ${count == 6
                ? 50
                : count == 5
                ? 25
                : 0} монет',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Подтвердить результат'));
        await tester.pumpAndSettle();
        expect(repo.mutations.single['completed_count'], count);
        expect(repo.mutations.single['task_version'], 7);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.client.close();
        repo.dispose();
      },
    );
  }

  testWidgets('calendar completion also asks for the graded result', (
    tester,
  ) async {
    final repo = ResultsFixture();
    final task =
        (repo.snapshot!['tasks'] as List).first as Map<String, dynamic>;
    task['reward_options'] = mathRewardExample();
    task['reward'] = 50;
    await mountFields(
      tester,
      SchoolScreen(
        repository: repo,
        gradesOnly: true,
        initialDay: DateTime(2026, 10, 12),
        perform: (action) async {
          await action();
        },
      ),
    );
    await revealField(
      tester,
      find.byKey(ValueKey('result-complete-${task['id']}')),
    );
    await tester.tap(find.byKey(ValueKey('result-complete-${task['id']}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-completed-count')),
      '5',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить результат'));
    await tester.pumpAndSettle();
    expect((repo.changes.single['body'] as Map)['completed_count'], 5);
    expect((repo.changes.single['body'] as Map)['action'], 'complete');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });

  test('fixed mode explicitly removes old tiers from an edit body', () {
    final values = {
      'reward_type': 'fixed',
      'reward': 12,
      'reward_options': mathRewardExample(),
      'due_at': DateTime.now(),
      'is_required': 'optional',
    };
    final body = taskCreateBody(values, null);
    expect(body['reward_options'], isNull);
    expect(body['reward'], 12);
  });
}
