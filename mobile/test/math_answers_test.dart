import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/math_answers.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_screen.dart';

import 'task_rules_test.dart' show TaskFixture;

class _MathRepository extends TaskFixture {
  final requests = <String>[];
  final responses = <String, Future<Map<String, dynamic>>>{};
  String? suggested = '2026-10-16';
  _MathRepository({String role = 'parent'})
    : super(userRole: role, withTask: true) {
    (snapshot!['tasks'] as List).first['status'] = 'submitted';
  }
  Map<String, dynamic> answers(String date) => {
    'date': date,
    'title': 'Занятие $date',
    'tasks': [
      for (var n = 1; n <= 6; n++)
        {
          'number': n,
          'title': 'Задача $n',
          'prompt': 'Условие задачи $n',
          'answer': 'PRIVATE_${date}_$n',
          'solution': 'Объяснение $n',
          'hint': 'Подсказка $n',
        },
    ],
  };
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) async {
    requests.add(path);
    if (responses.containsKey(path)) return responses[path]!;
    if (path.endsWith('math-answer-sessions')) {
      return {
        'suggested_date': suggested,
        'lessons': [
          for (final day in ['2026-10-14', '2026-10-16'])
            {'date': day, 'title': 'Занятие $day'},
        ],
      };
    }
    return answers(path.split('/').last);
  }

  void changeIdentity(String role) {
    token = role == 'none' ? null : 'different-session';
    generation++;
    snapshot!['user'] = {...snapshot!['user'] as Map, 'role': role};
    notifyListeners();
  }
}

void main() {
  Future<void> open(WidgetTester tester, _MathRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MathAnswersScreen(repository: repo, taskId: 'task'),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final role in ['parent', 'child', 'relative']) {
    testWidgets('review entry is available only to a parent: $role', (
      tester,
    ) async {
      final repo = _MathRepository(role: role);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskScreen(
              repository: repo,
              perform: (_) async {},
              reviewTaskId: 'task',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('math-answers-task')),
        role == 'parent' ? findsOneWidget : findsNothing,
      );
      expect(repo.requests, isEmpty);
    });
  }

  for (final role in ['child', 'relative']) {
    testWidgets('direct answer page cannot fetch content for $role', (
      tester,
    ) async {
      final repo = _MathRepository(role: role);
      await open(tester, repo);
      expect(repo.requests, isEmpty);
      expect(
        find.textContaining('Ответы доступны только родителям.'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE_'), findsNothing);
    });
  }

  testWidgets(
    'parent sees the exact selected day and explanations without snapshot caching',
    (tester) async {
      final repo = _MathRepository();
      final before = jsonEncode(repo.snapshot);
      await open(tester, repo);
      expect(repo.requests.last, '/v1/tasks/task/math-answers/2026-10-16');
      expect(find.text('Ответ: PRIVATE_2026-10-16_1'), findsOneWidget);
      await tester.tap(find.text('1. Задача 1'));
      await tester.pumpAndSettle();
      expect(find.text('Решение: Объяснение 1'), findsOneWidget);
      expect(find.text('Подсказка: Подсказка 1'), findsOneWidget);
      expect(jsonEncode(repo.snapshot), before);
    },
  );

  testWidgets('missing lesson day requires a choice instead of opening today', (
    tester,
  ) async {
    final repo = _MathRepository()..suggested = null;
    await open(tester, repo);
    expect(repo.requests, ['/v1/tasks/task/math-answer-sessions']);
    expect(find.textContaining('Выберите день из курса'), findsOneWidget);
    expect(find.textContaining('PRIVATE_'), findsNothing);
  });

  testWidgets('changing day ignores an earlier delayed answer response', (
    tester,
  ) async {
    final repo = _MathRepository();
    final old = Completer<Map<String, dynamic>>();
    repo.responses['/v1/tasks/task/math-answers/2026-10-16'] = old.future;
    await tester.pumpWidget(
      MaterialApp(
        home: MathAnswersScreen(repository: repo, taskId: 'task'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    // The deliberately pending lesson keeps its spinner animating.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('14.10.2026').last);
    await tester.pumpAndSettle();
    expect(find.text('Ответ: PRIVATE_2026-10-14_1'), findsOneWidget);
    old.complete(repo.answers('2026-10-16'));
    await tester.pumpAndSettle();
    expect(find.text('Ответ: PRIVATE_2026-10-14_1'), findsOneWidget);
    expect(find.textContaining('PRIVATE_2026-10-16'), findsNothing);
  });

  for (final nextRole in ['child', 'none', 'parent']) {
    testWidgets(
      'answers disappear immediately after session change to $nextRole',
      (tester) async {
        final repo = _MathRepository();
        await open(tester, repo);
        expect(find.textContaining('PRIVATE_'), findsWidgets);
        repo.changeIdentity(nextRole);
        await tester.pump();
        expect(find.textContaining('PRIVATE_'), findsNothing);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      },
    );
  }

  for (final status in [401, 403]) {
    testWidgets(
      'server revocation $status hides answers despite a cached parent role',
      (tester) async {
        final repo = _MathRepository();
        await open(tester, repo);
        final denied = Completer<Map<String, dynamic>>();
        repo.responses['/v1/tasks/task/math-answers/2026-10-14'] =
            denied.future;
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('14.10.2026').last);
        await tester.pump();
        denied.completeError(ApiFailure(status, 'Доступ отозван'));
        await tester.pumpAndSettle();
        expect(repo.role, 'parent');
        expect(find.textContaining('PRIVATE_'), findsNothing);
        expect(
          find.textContaining('Ответы доступны только родителям.'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('access revoked while loading cannot expose a delayed response', (
    tester,
  ) async {
    final repo = _MathRepository();
    final response = Completer<Map<String, dynamic>>();
    repo.responses['/v1/tasks/task/math-answers/2026-10-16'] = response.future;
    await tester.pumpWidget(
      MaterialApp(
        home: MathAnswersScreen(repository: repo, taskId: 'task'),
      ),
    );
    await tester.pump();
    await tester.pump();
    repo.changeIdentity('child');
    await tester.pump();
    response.complete(repo.answers('2026-10-16'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE_'), findsNothing);
  });

  testWidgets('small phone with large text can scroll to the sixth answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _MathRepository();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: MathAnswersScreen(repository: repo, taskId: 'task'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ответ: PRIVATE_2026-10-16_6'),
      300,
    );
    expect(find.text('Ответ: PRIVATE_2026-10-16_6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
