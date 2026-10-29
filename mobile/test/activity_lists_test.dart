import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/activity_lists.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/visuals.dart';

class ActivityFixture extends FamilyRepository {
  final changes = <String>[];
  ActivityFixture() {
    final now = familyClock(null);
    String due(int days) =>
        DateTime.utc(now.year, now.month, now.day + days, 12).toIso8601String();
    online = true;
    snapshot = {
      'user': {'id': 'dad', 'role': 'parent'},
      'family': {'timezone': 'Europe/Moscow'},
      'balance': {'available': 0, 'total': 0, 'reserved': 0},
      'members': [
        {'id': 'dad', 'name': 'Папа'},
        {'id': 'mom', 'name': 'Мама'},
      ],
      'tasks': [
        for (var i = 0; i < 30; i++)
          {'title': 'Сегодня $i', 'due_at': due(0), 'status': 'assigned'},
        {'title': 'Далёкое задание', 'due_at': due(30), 'status': 'assigned'},
        {
          'title': 'Просроченное задание',
          'due_at': due(-1),
          'status': 'returned',
        },
        {'title': 'Старый результат', 'due_at': due(-5), 'status': 'completed'},
        {'title': 'Результат сегодня', 'due_at': due(0), 'status': 'completed'},
      ],
      'audit': [
        for (var i = 0; i < 130; i++)
          {
            'action': i < 100 ? 'task.created' : 'grade.saved',
            'actor_id': i < 100 ? 'dad' : 'mom',
            'created_at': DateTime.now()
                .toUtc()
                .subtract(Duration(minutes: i))
                .toIso8601String(),
          },
        {
          'action': 'schedule.saved',
          'actor_id': 'dad',
          'created_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 40))
              .toIso8601String(),
        },
      ],
      'penalties': [
        {
          'id': 'fine',
          'status': 'pending',
          'reason': 'Срок задания: Умывание с чисткой зубов',
          'amount': 500,
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
    changes.add(path);
    return {'ok': true};
  }
}

Future<void> select(WidgetTester tester, String label, String text) async {
  final filter = find.byWidgetPredicate(
    (widget) => widget is ActivityFilter && widget.label == label,
  );
  await tester.ensureVisible(filter);
  await tester.tap(
    find.descendant(of: filter, matching: find.byType(DropdownButton<String>)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  late ActivityFixture repo;
  setUp(() => repo = ActivityFixture());
  tearDown(() {
    repo.client.close();
    repo.dispose();
  });

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    double scale = 1.6,
  }) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: familyTheme(false),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'today filters hide distant repeats, include overdue and results, and list scrolls independently',
    (tester) async {
      var opened = false;
      await show(
        tester,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TodayTaskList(repository: repo, onOpen: () => opened = true),
            const Text('Следующая карточка'),
          ],
        ),
      );
      expect(find.text('Найдено: 32'), findsOneWidget);
      expect(find.text('Далёкое задание'), findsNothing);
      final window = find.byType(ActivityWindow);
      final scrollable = find.descendant(
        of: window,
        matching: find.byType(Scrollable),
      );
      final before = tester.getTopLeft(find.text('Следующая карточка'));
      await tester.scrollUntilVisible(
        find.text('Сегодня 29'),
        250,
        scrollable: scrollable,
      );
      expect(tester.getTopLeft(find.text('Следующая карточка')), before);
      await select(tester, 'Состояние задания', 'Выполнено');
      expect(find.text('Найдено: 1'), findsOneWidget);
      expect(find.text('Результат сегодня'), findsOneWidget);
      await tester.tap(find.text('Результат сегодня'));
      expect(opened, true);
      await select(tester, 'Период заданий', 'Все даты');
      expect(find.text('Найдено: 2'), findsOneWidget);
      await select(tester, 'Состояние задания', 'Не выполнено');
      expect(find.text('По выбранным фильтрам заданий нет'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history reaches entries beyond 100 and combines period, action and actor',
    (tester) async {
      await show(
        tester,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [ActionHistory(repository: repo)],
        ),
        scale: 1,
      );
      expect(find.text('Найдено: 130'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('history-row-110')),
        200,
        maxScrolls: 100,
        scrollable: find.descendant(
          of: find.byType(ActivityWindow),
          matching: find.byType(Scrollable),
        ),
      );
      await select(tester, 'Вид действия', 'Предметы и оценки');
      expect(find.text('Найдено: 30'), findsOneWidget);
      await select(tester, 'Участник', 'Папа');
      expect(find.text('По выбранным фильтрам действий нет'), findsOneWidget);
      await select(tester, 'Участник', 'Все участники');
      await select(tester, 'Вид действия', 'Календарь');
      expect(find.text('Найдено: 0'), findsOneWidget);
      await select(tester, 'Период истории', 'Вся доступная история');
      expect(find.text('Найдено: 1'), findsOneWidget);
      expect(find.text('Сохранено занятие'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'penalty text spans card width and buttons remain below it with large text',
    (tester) async {
      repo.token = 'synthetic-penalty-layout-owner';
      await show(
        tester,
        MoneyScreen(
          repository: repo,
          perform: (action) async {
            await action();
          },
        ),
        scale: 2,
      );
      final reason = find.text('Срок задания: Умывание с чисткой зубов');
      await tester.scrollUntilVisible(
        reason,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getSize(reason).width, greaterThan(235));
      await tester.scrollUntilVisible(
        find.text('Применить'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final amount = find.textContaining('При подтверждении спишется: 500');
      expect(
        tester.getTopLeft(find.text('Применить')).dy,
        greaterThan(tester.getBottomLeft(amount).dy),
      );
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(find.text('Штраф: 500 монет'), findsOneWidget);
      expect(repo.changes, isEmpty);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Отменить'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(repo.changes, ['/v1/penalties/fine/waive']);
      expect(tester.takeException(), isNull);
    },
  );
}
