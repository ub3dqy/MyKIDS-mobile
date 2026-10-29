import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/main.dart' show TodayScreen;
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/schedule.dart';

import 'field_layout_test.dart' show mountFields, revealField;
import 'task_time_labels_test.dart' show TaskTimeFixture;

class CountersFixture extends TaskTimeFixture {
  CountersFixture({super.role = 'parent'}) {
    final now = familyClock(snapshot);
    String due(int offset) => DateTime.utc(
      now.year,
      now.month,
      now.day + offset,
      12,
    ).toIso8601String();
    final base = rows('tasks').first;
    snapshot!['tasks'] = [
      {
        ...base,
        'id': 'today-done',
        'title': 'Сегодня выполнено',
        'status': 'completed',
        'planned_start': null,
        'planned_end': null,
        'due_at': due(0),
      },
      {
        ...base,
        'id': 'today-review',
        'title': 'Сегодня на проверке',
        'status': 'submitted',
        'planned_start': null,
        'planned_end': null,
        'due_at': due(0),
      },
      {
        ...base,
        'id': 'overdue',
        'title': 'Вчера вернули',
        'status': 'returned',
        'planned_start': null,
        'planned_end': null,
        'due_at': due(-1),
      },
      {
        ...base,
        'id': 'old-done',
        'title': 'Вчера выполнено',
        'status': 'completed',
        'planned_start': null,
        'planned_end': null,
        'due_at': due(-1),
      },
      {
        ...base,
        'id': 'tomorrow',
        'title': 'Завтра',
        'status': 'assigned',
        'planned_start': null,
        'planned_end': null,
        'due_at': due(1),
      },
    ];
    snapshot!['balance'] = {'total': 100, 'reserved': 50, 'available': 50};
    snapshot!['redemptions'] = [
      {
        'id': 'first',
        'title': 'Первая заявка',
        'amount': 25,
        'status': 'pending',
      },
      {
        'id': 'second',
        'title': 'Вторая заявка',
        'amount': 25,
        'status': 'claimed',
        'claimed_by': userId,
      },
      {
        'id': 'old',
        'title': 'Выданная заявка',
        'amount': 25,
        'status': 'confirmed',
      },
    ];
    snapshot!['penalties'] = [
      {
        'id': 'fine',
        'reason': 'Срок задания',
        'amount': 500,
        'status': 'pending',
      },
    ];
  }
  void approved() {
    (snapshot!['tasks'] as List).firstWhere(
      (t) => t['id'] == 'today-review',
    )['status'] = 'completed';
    notifyListeners();
  }

  void firstPaid() {
    (snapshot!['redemptions'] as List).first['status'] = 'confirmed';
    snapshot!['balance'] = {'total': 75, 'reserved': 25, 'available': 50};
    notifyListeners();
  }

  void secondCancelled() {
    (snapshot!['redemptions'] as List)[1]['status'] = 'rejected';
    snapshot!['balance'] = {'total': 75, 'reserved': 0, 'available': 75};
    notifyListeners();
  }

  void fineApplied() {
    (snapshot!['penalties'] as List).single['status'] = 'applied';
    snapshot!['balance'] = {'total': -425, 'reserved': 0, 'available': -425};
    notifyListeners();
  }
}

Future<void> showCounters(
  WidgetTester tester,
  CountersFixture repo,
  Widget Function() screen, {
  Size? size = const Size(360, 900),
}) => mountFields(
  tester,
  Scaffold(
    body: AnimatedBuilder(animation: repo, builder: (_, _) => screen()),
  ),
  child: repo.role == 'child',
  scale: 1.2,
  screenSize: size,
);

void main() {
  late CountersFixture repo;
  tearDown(() {
    repo.client.close();
    repo.dispose();
  });

  testWidgets(
    'child daily progress excludes past completions and future assignments',
    (tester) async {
      repo = CountersFixture(role: 'child');
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showCounters(
        tester,
        repo,
        () => ChildToday(repository: repo, openPage: (_) {}),
      );
      await revealField(tester, find.text('Проверено 1 из 3'));
      expect(find.text('На проверке: 1. Ты молодец!'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('today-task-progress')),
            )
            .value,
        closeTo(1 / 3, .001),
      );
      repo.approved();
      await tester.pumpAndSettle();
      expect(find.text('Проверено 2 из 3'), findsOneWidget);
      expect(find.textContaining('На проверке:'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('today-task-progress')),
            )
            .value,
        closeTo(2 / 3, .001),
      );
      final task = (repo.snapshot!['tasks'] as List).firstWhere(
        (t) => t['id'] == 'overdue',
      );
      task['status'] = 'cancelled';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Проверено 2 из 2'), findsOneWidget);
    },
  );

  testWidgets('parent review and open request counts follow server states', (
    tester,
  ) async {
    repo = CountersFixture();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showCounters(
      tester,
      repo,
      () => TodayScreen(repository: repo, openPage: (_) {}),
    );
    await revealField(tester, find.text('Результатов на проверке: 1'));
    repo.approved();
    await tester.pumpAndSettle();
    expect(find.text('Результатов на проверке: 0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('today-review-today-review')),
      findsNothing,
    );
    expect(find.text('Заявок на награды и деньги: 2'), findsOneWidget);
    repo.firstPaid();
    await tester.pumpAndSettle();
    expect(find.text('Заявок на награды и деньги: 1'), findsOneWidget);
    repo.secondCancelled();
    await tester.pumpAndSettle();
    expect(find.text('Заявок на награды и деньги: 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'money totals, reservations and pending penalties update independently',
    (tester) async {
      repo = CountersFixture();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showCounters(
        tester,
        repo,
        () => MoneyScreen(
          repository: repo,
          perform: (_) async => fail('Viewing must not move money'),
        ),
      );
      expect(
        find.text('Всего: 100 · в заявках: 50 · доступно: 50'),
        findsOneWidget,
      );
      repo.firstPaid();
      await tester.pumpAndSettle();
      expect(
        find.text('Всего: 75 · в заявках: 25 · доступно: 50'),
        findsOneWidget,
      );
      repo.secondCancelled();
      await tester.pumpAndSettle();
      expect(
        find.text('Всего: 75 · в заявках: 0 · доступно: 75'),
        findsOneWidget,
      );
      await revealField(tester, find.text('Штрафы ждут подтверждения: 1'));
      repo.fineApplied();
      await tester.pumpAndSettle();
      expect(find.text('Штрафы ждут подтверждения: 0'), findsOneWidget);
      await revealField(
        tester,
        find.text('Всего: -425 · в заявках: 0 · доступно: -425'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('today counters use planned date and the family timezone', () {
    repo = CountersFixture();
    final now = familyClock(repo.snapshot);
    final day = dateOnly(now);
    final task = {
      'status': 'assigned',
      'planned_start': '${day}T08:00:00+03:00',
      'due_at': DateTime.utc(
        now.year,
        now.month,
        now.day + 1,
        12,
      ).toIso8601String(),
    };
    expect(taskIsForToday(repo.snapshot, task), true);
    task['planned_start'] = DateTime.utc(
      now.year,
      now.month,
      now.day + 2,
      12,
    ).toIso8601String();
    task['due_at'] = '${day}T23:00:00+03:00';
    expect(taskIsForToday(repo.snapshot, task), false);
    expect(
      taskIsForToday(repo.snapshot, {
        'status': 'returned',
        'due_at': DateTime.utc(
          now.year,
          now.month,
          now.day - 2,
          12,
        ).toIso8601String(),
      }),
      true,
    );
  });
}
