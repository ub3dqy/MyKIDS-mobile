import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'task_rules_test.dart' show TaskFixture, showTasks, reveal;

class TaskEditFixture extends TaskFixture {
  TaskEditFixture({super.userRole, super.withTask}) {
    (snapshot!['members'] as List).add({
      'id': 'mother',
      'name': 'Мама',
      'role': 'parent',
      'active': 1,
    });
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    if (method != 'PUT') {
      return super.mutate(
        path,
        body,
        method: method,
        offlineSubmission: offlineSubmission,
        files: files,
      );
    }
    mutations.add({'path': path, 'method': method, ...body});
    final task = (snapshot!['tasks'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((item) => path.endsWith('/${item['id']}'));
    final version = task['version'] as int;
    task.addAll(body);
    task['version'] = version + 1;
    task['is_required'] = body['is_required'] == true ? 1 : 0;
    task['require_photo'] = body['require_photo'] == true ? 1 : 0;
    notifyListeners();
    return {'id': task['id'], 'version': task['version']};
  }
}

Future<void> selectOptional(WidgetTester tester) async {
  await reveal(tester, find.byKey(const ValueKey('field-is_required')));
  await tester.tap(find.byKey(const ValueKey('field-is_required')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Необязательное').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'repeat editing offers one day or future days and serializes the existing schedule',
    (tester) async {
      final repo = TaskEditFixture(withTask: true);
      (repo.snapshot!['tasks'] as List).first['recurrence_id'] = 'daily';
      repo.snapshot!['task_recurrences'] = [
        {
          'id': 'daily',
          'active': 1,
          'weekdays': jsonEncode([1, 3, 5]),
          'until': null,
        },
      ];
      await showTasks(tester, repo);
      // The fixture's old due date is yesterday: inspect all pending tasks as an adult.
      await tester.tap(find.text('Ждут внимания'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Убрать игрушки'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Редактировать задание'));
      await tester.tap(find.text('Редактировать задание'));
      await tester.pumpAndSettle();
      expect(find.text('Только этот день'), findsOneWidget);
      await tester.tap(find.text('Этот и следующие дни'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-title')),
        'Новые условия',
      );
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['scope'], 'future');
      expect(repo.mutations.single['weekdays'], [1, 3, 5]);
      expect(repo.mutations.single['task_version'], 7);
      expect(tester.takeException(), isNull);
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets(
    'a revoked reviewer is shown without a dropdown crash and must be replaced',
    (tester) async {
      final repo = TaskEditFixture(withTask: true);
      (repo.snapshot!['tasks'] as List).first['reviewer_id'] = 'revoked';
      await showTasks(tester, repo);
      await tester.tap(find.text('Убрать игрушки'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Редактировать задание'));
      await tester.tap(find.text('Редактировать задание'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Выберите доступного проверяющего'),
        findsWidgets,
      );
      expect(repo.mutations, isEmpty);
      expect(tester.takeException(), isNull);
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets(
    'either parent is an explicit default alongside each parent and zero reward saves',
    (tester) async {
      final repo = TaskEditFixture();
      (repo.snapshot!['members'] as List).add({
        'id': 'child',
        'name': 'Ребёнок',
        'role': 'child',
        'active': 1,
        'review_tasks': 1,
      });
      await showTasks(tester, repo);
      await tester.tap(find.text('Добавить задание'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-title')),
        'Без монет',
      );
      await selectOptional(tester);
      await reveal(tester, find.byKey(const ValueKey('field-reviewer_id')));
      await tester.tap(find.byKey(const ValueKey('field-reviewer_id')));
      await tester.pumpAndSettle();
      expect(find.text('Мама'), findsOneWidget);
      expect(find.text('Папа'), findsOneWidget);
      expect(find.text('Ребёнок'), findsNothing);
      await tester.tap(find.text('Мама или папа').last);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['reward'], 0);
      expect(repo.mutations.single['reviewer_id'], isNull);
      expect(repo.mutations.single['penalty'], 0);
      expect(tester.takeException(), isNull);
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets(
    'editing prefills existing fields updates the same task and displays no reward',
    (tester) async {
      final repo = TaskEditFixture(withTask: true);
      final originalDue = repo.rows('tasks').first['due_at'] as String;
      await showTasks(tester, repo);
      await tester.tap(find.text('Убрать игрушки'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Редактировать задание'));
      await tester.tap(find.text('Редактировать задание'));
      await tester.pumpAndSettle();
      expect(find.text('Изменить задание'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Убрать игрушки'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('field-title')),
        'Новое название',
      );
      await reveal(tester, find.byKey(const ValueKey('field-reward')));
      await tester.enterText(find.byKey(const ValueKey('field-reward')), '0');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      final saved = repo.mutations.single;
      expect(saved['path'], '/v1/tasks/task');
      expect(saved['method'], 'PUT');
      expect(saved['task_version'], 7);
      expect(saved['scope'], 'single');
      expect(
        DateTime.parse(saved['due_at'] as String),
        DateTime.parse(originalDue),
      );
      expect(saved['description'], 'Убрать в коробку');
      expect(find.text('Новое название'), findsOneWidget);
      expect(find.textContaining('Награды за выполнение нет.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets('child and already submitted work have no edit action', (
    tester,
  ) async {
    final child = TaskEditFixture(userRole: 'child', withTask: true);
    await showTasks(tester, child);
    await tester.tap(find.text('Убрать игрушки'));
    await tester.pumpAndSettle();
    expect(find.text('Редактировать задание'), findsNothing);
    final parent = TaskEditFixture(withTask: true);
    (parent.snapshot!['tasks'] as List).first['status'] = 'submitted';
    await showTasks(tester, parent);
    await tester.tap(find.text('Убрать игрушки'));
    await tester.pumpAndSettle();
    expect(find.text('Редактировать задание'), findsNothing);
    expect(tester.takeException(), isNull);
    for (final repo in [child, parent]) {
      repo.client.close();
      repo.dispose();
    }
  });
}
