import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

class TaskFixture extends FamilyRepository {
  final mutations = <Map<String, dynamic>>[];
  TaskFixture({String userRole = 'parent', bool withTask = false}) {
    token = 'synthetic';
    online = true;
    snapshot = {
      'user': {
        'id': userRole == 'child' ? 'child' : 'parent',
        'role': userRole,
        'create_tasks': 1,
        'review_tasks': 1,
      },
      'family': {'timezone': 'Europe/Moscow'},
      'members': [
        {'id': 'parent', 'name': 'Папа', 'role': 'parent', 'active': 1},
      ],
      'subjects': <Map<String, dynamic>>[],
      'programs': <Map<String, dynamic>>[],
      'tasks': [
        if (withTask)
          {
            'id': 'task',
            'title': 'Убрать игрушки',
            'description': 'Убрать в коробку',
            'author_id': 'parent',
            'reviewer_id': null,
            'status': 'assigned',
            'due_at': DateTime.now()
                .subtract(const Duration(days: 1))
                .toUtc()
                .toIso8601String(),
            'version': 7,
            'reward': 30,
            'penalty': 15,
            'is_required': 1,
            'financial_approved': 1,
            'note': '',
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    mutations.add({'path': path, ...body});
    if (body['action'] == 'not_completed') {
      (snapshot!['tasks'] as List).first['status'] = 'not_completed';
      notifyListeners();
    }
    return {
      'ids': ['new'],
      'status': 'not_completed',
    };
  }
}

Future<void> showTasks(WidgetTester tester, TaskFixture repo) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: repo,
          builder: (context, _) => TaskScreen(
            repository: repo,
            perform: (operation) async {
              await operation();
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .last,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  testWidgets(
    'optional tasks hide the penalty and submit zero with an explicit type',
    (tester) async {
      final repo = TaskFixture();
      await showTasks(tester, repo);
      await tester.tap(find.text('Добавить задание'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-title')),
        'Полить цветы',
      );
      await reveal(tester, find.byKey(const ValueKey('field-is_required')));
      await tester.tap(find.byKey(const ValueKey('field-is_required')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Необязательное').last);
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('field-reward')));
      await tester.enterText(find.byKey(const ValueKey('field-reward')), '30');
      expect(find.byKey(const ValueKey('field-penalty')), findsNothing);
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['is_required'], isFalse);
      expect(repo.mutations.single['penalty'], 0);
      expect(repo.mutations.single['reward'], 30);
      expect(tester.takeException(), isNull);
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets(
    'missing mandatory penalty keeps the form and reveals its exact field',
    (tester) async {
      final repo = TaskFixture();
      await showTasks(tester, repo);
      await tester.tap(find.text('Добавить задание'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('field-title')),
        'Убрать игрушки',
      );
      await reveal(tester, find.byKey(const ValueKey('field-reward')));
      await tester.enterText(find.byKey(const ValueKey('field-reward')), '30');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Укажите штраф: не менее 1 монеты'), findsOneWidget);
      expect(repo.mutations, isEmpty);
      expect(find.byKey(const ValueKey('field-penalty')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-penalty')), '15');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['is_required'], isTrue);
      expect(repo.mutations.single['penalty'], 15);
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets(
    'adult failure needs confirmation and sends the displayed task version once',
    (tester) async {
      final repo = TaskFixture(withTask: true);
      await showTasks(tester, repo);
      await tester.tap(find.text('Убрать игрушки'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Не выполнено — назначить штраф'));
      await tester.tap(find.text('Не выполнено — назначить штраф'));
      await tester.pumpAndSettle();
      expect(repo.mutations, isEmpty);
      await tester.tap(find.text('Вернуться'));
      await tester.pumpAndSettle();
      expect(repo.mutations, isEmpty);
      await tester.tap(find.text('Не выполнено — назначить штраф'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Списать 15 монет'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['task_version'], 7);
      expect(repo.mutations.single['action'], 'not_completed');
      expect(find.text('Не выполнено — назначить штраф'), findsNothing);
      expect(find.text('Готово — отправить на проверку'), findsNothing);
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets(
    'child sees the agreed penalty but cannot confirm noncompletion',
    (tester) async {
      final repo = TaskFixture(userRole: 'child', withTask: true);
      await showTasks(tester, repo);
      await reveal(tester, find.text('Убрать игрушки'));
      await tester.tap(find.text('Убрать игрушки'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Штраф за невыполнение: 15'), findsOneWidget);
      expect(find.text('Не выполнено — назначить штраф'), findsNothing);
      expect(repo.mutations, isEmpty);
      repo.client.close();
      repo.dispose();
    },
  );
}
