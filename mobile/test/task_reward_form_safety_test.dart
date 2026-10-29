import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/task_rewards.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'task_edit_test.dart' show TaskEditFixture;
import 'task_rules_test.dart' show reveal;

class FormSafetyFixture extends TaskEditFixture {
  final writes = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? saveReply;
  bool failNext = false;

  FormSafetyFixture({bool child = false})
    : super(userRole: child ? 'child' : 'parent', withTask: true) {
    snapshot!.addAll({
      'balance': {'total': 50, 'reserved': 0, 'available': 50},
      'rewards': [
        {
          'id': 'gift',
          'title': 'Конструктор',
          'description': 'Личный подарок',
          'price': 25,
          'available': 1,
          'revision': 'a' * 64,
        },
      ],
      'penalties': <Map<String, dynamic>>[],
      'redemptions': <Map<String, dynamic>>[],
      'ledger': <Map<String, dynamic>>[],
      'grade_rules': <Map<String, dynamic>>[],
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
    writes.add({
      'path': path,
      'method': method,
      'body': Map<String, dynamic>.from(body),
      'user': userId,
      'offlineSubmission': offlineSubmission,
    });
    if (failNext) {
      failNext = false;
      throw Exception('Synthetic connection interruption');
    }
    return saveReply == null ? {'ok': true} : saveReply!.future;
  }
}

Future<void> mountSafety(
  WidgetTester tester,
  FormSafetyFixture repo, {
  required bool money,
  ValueNotifier<FormSafetyFixture>? selection,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    if (repo.saveReply?.isCompleted == false) {
      repo.saveReply!.complete({'ok': true});
    }
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([repo, ?selection]),
          builder: (_, _) => money
              ? MoneyScreen(
                  repository: selection?.value ?? repo,
                  perform: (operation) async {
                    await operation();
                  },
                )
              : TaskScreen(
                  repository: selection?.value ?? repo,
                  perform: (operation) async {
                    await operation();
                  },
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openTaskDecision(WidgetTester tester, String operation) async {
  if (['stop_repeat', 'edit_repeat'].contains(operation)) {
    await tester.tap(find.text('Ждут внимания'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Убрать игрушки'));
  await tester.pumpAndSettle();
  final label = {
    'stop_repeat': 'Остановить повторение',
    'edit_repeat': 'Редактировать задание',
    'not_completed': 'Не выполнено — назначить штраф',
    'approve': 'Подтвердить выполнение',
    'return': 'Нужно исправить',
  }[operation]!;
  await reveal(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  if (operation == 'approve') {
    await tester.enterText(
      find.byKey(const ValueKey('task-completed-count')),
      '6',
    );
    await tester.pumpAndSettle();
  } else if (operation == 'return') {
    await tester.enterText(
      find.byKey(const ValueKey('field-note')),
      'Личное замечание',
    );
    await tester.pump();
  }
}

void prepareDecision(FormSafetyFixture repo, String operation) {
  final task = (repo.snapshot!['tasks'] as List).first as Map<String, dynamic>;
  if (['stop_repeat', 'edit_repeat'].contains(operation)) {
    task['recurrence_id'] = 'daily';
    repo.snapshot!['task_recurrences'] = [
      {'id': 'daily', 'active': 1, 'weekdays': '[1,3,5]', 'until': null},
    ];
  }
  if (['approve', 'return'].contains(operation)) {
    task['status'] = 'submitted';
    task['reward_options'] = mathRewardExample();
  }
}

Future<void> openSafetyForm(WidgetTester tester, String operation) async {
  if (['edit_task', 'plan', 'cancel', 'reschedule'].contains(operation)) {
    await tester.tap(find.text('Убрать игрушки'));
    await tester.pumpAndSettle();
  } else if (operation == 'edit_reward') {
    await reveal(tester, find.text('Конструктор · 25 монет'));
    await tester.tap(find.text('Конструктор · 25 монет'));
    await tester.pumpAndSettle();
  }
  final label = {
    'create_task': 'Добавить задание',
    'edit_task': 'Редактировать задание',
    'plan': 'Время в календаре',
    'cancel': 'Отменить',
    'reschedule': 'Перенести',
    'create_reward': 'Добавить награду',
    'edit_reward': 'Изменить награду',
    'grade_rules': 'Настроить суммы за оценки',
    'cash_request': 'Обменять монеты на рубли',
  }[operation]!;
  await reveal(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  final title = find.byKey(const ValueKey('field-title'));
  if (title.evaluate().isNotEmpty) {
    await tester.enterText(title, 'Личные условия первой семьи');
    await tester.pump();
  }
  if (operation == 'create_task') {
    final penalty = find.byKey(const ValueKey('field-penalty'));
    await reveal(tester, penalty);
    await tester.enterText(penalty, '15');
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  const operations = [
    'create_task',
    'edit_task',
    'plan',
    'cancel',
    'reschedule',
    'create_reward',
    'edit_reward',
    'grade_rules',
    'cash_request',
  ];
  for (final operation in operations) {
    testWidgets('$operation cannot save through a different family access', (
      tester,
    ) async {
      final repo = FormSafetyFixture(child: operation == 'cash_request');
      await mountSafety(
        tester,
        repo,
        money: operations.indexOf(operation) >= 5,
      );
      await openSafetyForm(tester, operation);
      repo.token = 'another-family-session';
      repo.generation++;
      repo.snapshot!['user']['id'] = 'another-family-user';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Сохранить');
      if (save.evaluate().isNotEmpty) {
        await reveal(tester, save);
        if (tester.widget<FilledButton>(save).onPressed != null) {
          await tester.tap(save);
        }
        await tester.pumpAndSettle();
      }
      expect(
        repo.writes,
        isEmpty,
        reason: 'An old form must never save using the new family session.',
      );
      expect(find.text('Личные условия первой семьи'), findsNothing);
      expect(find.textContaining('доступ измен'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a connection interruption retains the reward draft for one explicit retry',
    (tester) async {
      final repo = FormSafetyFixture()..failNext = true;
      await mountSafety(tester, repo, money: true);
      await openSafetyForm(tester, 'create_reward');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
      expect(find.text('Личные условия первой семьи'), findsOneWidget);
      expect(find.textContaining('Попробуйте ещё раз'), findsOneWidget);
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(2));
      expect(repo.writes.last['body'], repo.writes.first['body']);
      expect(find.byKey(const ValueKey('field-title')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a pending save cannot open a date picker or change its submitted draft',
    (tester) async {
      final repo = FormSafetyFixture()
        ..saveReply = Completer<Map<String, dynamic>>();
      await mountSafety(tester, repo, money: false);
      await openSafetyForm(tester, 'create_task');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      expect(repo.writes, hasLength(1));
      await reveal(tester, find.textContaining('Срок выполнения:'));
      await tester.tap(
        find.textContaining('Срок выполнения:'),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.byType(DatePickerDialog), findsNothing);
      repo.saveReply!.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(repo.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['logout', 'endpoint', 'role', 'generation', 'user']) {
    testWidgets('a reward draft closes its access after $change', (
      tester,
    ) async {
      final repo = FormSafetyFixture();
      await mountSafety(tester, repo, money: true);
      await openSafetyForm(tester, 'create_reward');
      switch (change) {
        case 'logout':
          repo.token = null;
        case 'endpoint':
          repo.endpoint = 'https://other-synthetic-family.invalid';
        case 'role':
          repo.snapshot!['user']['role'] = 'relative';
        case 'generation':
          repo.generation++;
        case 'user':
          repo.snapshot!['user']['id'] = 'different-parent';
      }
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-title')), findsNothing);
      expect(find.textContaining('доступ измен'), findsWidgets);
      expect(repo.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final money in [true, false]) {
    testWidgets(
      'replacing the repository masks an open ${money ? 'reward' : 'task'} form',
      (tester) async {
        final repo = FormSafetyFixture();
        final replacement = FormSafetyFixture()..token = 'replacement';
        final selection = ValueNotifier(repo);
        addTearDown(() {
          selection.dispose();
          replacement.client.close();
          replacement.dispose();
        });
        await mountSafety(tester, repo, money: money, selection: selection);
        await openSafetyForm(tester, money ? 'create_reward' : 'create_task');
        selection.value = replacement;
        await tester.pumpAndSettle();
        expect(find.text('Личные условия первой семьи'), findsNothing);
        expect(find.textContaining('доступ измен'), findsWidgets);
        expect(repo.writes, isEmpty);
        expect(replacement.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a brief connection loss preserves a draft and never saves it automatically',
    (tester) async {
      final repo = FormSafetyFixture();
      await mountSafety(tester, repo, money: true);
      await openSafetyForm(tester, 'create_reward');
      repo.online = false;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Сохранить'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Сохранить'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Личные условия первой семьи'), findsOneWidget);
      expect(find.textContaining('Введённые данные сохранены'), findsOneWidget);
      repo.online = true;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
      expect(
        (repo.writes.single['body'] as Map)['title'],
        'Личные условия первой семьи',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('planning a task remains available offline for the same owner', (
    tester,
  ) async {
    final repo = FormSafetyFixture();
    await mountSafety(tester, repo, money: false);
    await openSafetyForm(tester, 'plan');
    repo.online = false;
    repo.notifyListeners();
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repo.writes, hasLength(1));
    expect(repo.writes.single['offlineSubmission'], isTrue);
    expect(repo.writes.single['user'], 'parent');
    expect(tester.takeException(), isNull);
  });

  for (final operation in [
    'stop_repeat',
    'edit_repeat',
    'not_completed',
    'approve',
    'return',
  ]) {
    testWidgets('$operation hides its old decision after an account change', (
      tester,
    ) async {
      final repo = FormSafetyFixture();
      prepareDecision(repo, operation);
      await mountSafety(tester, repo, money: false);
      await openTaskDecision(tester, operation);
      repo.token = 'changed-account';
      repo.generation++;
      repo.snapshot!['user']['id'] = 'new-parent';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.textContaining('доступ измен'), findsWidgets);
      expect(find.byKey(const ValueKey('task-completed-count')), findsNothing);
      expect(find.byKey(const ValueKey('field-note')), findsNothing);
      expect(find.textContaining('Списать '), findsNothing);
      expect(find.text('Подтвердить результат'), findsNothing);
      expect(find.text('Этот и следующие дни'), findsNothing);
      expect(repo.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final operation in ['create_task', 'approve']) {
    testWidgets(
      '$operation cannot revive after a relative permission was revoked and restored',
      (tester) async {
        final repo = FormSafetyFixture();
        repo.snapshot!['user']['role'] = 'relative';
        prepareDecision(repo, operation);
        await mountSafety(tester, repo, money: false);
        if (operation == 'create_task') {
          await openSafetyForm(tester, operation);
        } else {
          await openTaskDecision(tester, operation);
        }
        final permission = operation == 'create_task'
            ? 'create_tasks'
            : 'review_tasks';
        repo.snapshot!['user'][permission] = 0;
        repo.notifyListeners();
        repo.snapshot!['user'][permission] = 1;
        repo.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.textContaining('доступ измен'), findsWidgets);
        expect(find.byKey(const ValueKey('field-title')), findsNothing);
        expect(
          find.byKey(const ValueKey('task-completed-count')),
          findsNothing,
        );
        expect(repo.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'duplicate open and duplicate result confirmation keep the task route intact',
    (tester) async {
      final repo = FormSafetyFixture();
      prepareDecision(repo, 'approve');
      await mountSafety(tester, repo, money: false);
      await tester.tap(find.text('Убрать игрушки'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Подтвердить выполнение'));
      final open = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить выполнение'),
          )
          .onPressed!;
      open();
      open();
      await tester.pumpAndSettle();
      expect(find.text('Сколько задач решено верно из 6?'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('task-completed-count')),
        '6',
      );
      await tester.pumpAndSettle();
      final confirm = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить результат'),
          )
          .onPressed!;
      confirm();
      confirm();
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
      expect((repo.writes.single['body'] as Map)['completed_count'], 6);
      expect(find.byType(TaskScreen), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a late failed save cannot validate a form hidden after an account change',
    (tester) async {
      final repo = FormSafetyFixture()
        ..saveReply = Completer<Map<String, dynamic>>();
      await mountSafety(tester, repo, money: true);
      await openSafetyForm(tester, 'create_reward');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      expect(repo.writes, hasLength(1));
      repo.token = 'changed-during-save';
      repo.generation++;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-title')), findsNothing);
      expect(find.textContaining('доступ измен'), findsOneWidget);
      repo.saveReply!.completeError(
        ApiFailure(401, 'Семейный доступ изменился'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('доступ измен'), findsOneWidget);
      expect(find.text('Сохранить'), findsNothing);
      expect(repo.writes, hasLength(1));
    },
  );

  testWidgets(
    'a late reply cannot close a new route after the old owner left',
    (tester) async {
      final repo = FormSafetyFixture()
        ..saveReply = Completer<Map<String, dynamic>>();
      await mountSafety(tester, repo, money: true);
      await openSafetyForm(tester, 'create_reward');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      expect(repo.writes, hasLength(1));
      repo.token = 'next-session';
      repo.generation++;
      repo.notifyListeners();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Новый экран')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.saveReply!.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(find.text('Новый экран'), findsOneWidget);
      expect(repo.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a correction form cannot send after the opened task revision changes',
    (tester) async {
      final repo = FormSafetyFixture();
      prepareDecision(repo, 'return');
      await mountSafety(tester, repo, money: false);
      await openTaskDecision(tester, 'return');
      final save = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'))
          .onPressed!;
      repo.snapshot!['tasks'] = [
        {...repo.rows('tasks').single, 'version': 8},
      ];
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Сохранить'), findsNothing);
      expect(find.textContaining('откройте её заново'), findsOneWidget);
      save();
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a program draft cannot outlive its family access', (
    tester,
  ) async {
    final repo = FormSafetyFixture();
    await mountSafety(tester, repo, money: false);
    await tester.tap(find.byTooltip('Другие действия с заданиями'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать программу из заданий'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('field-title')),
      'Личная программа семьи',
    );
    repo.token = 'changed-program-owner';
    repo.generation++;
    repo.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Личная программа семьи'), findsNothing);
    expect(find.textContaining('доступ измен'), findsOneWidget);
    expect(repo.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
