import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/activity_lists.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/main.dart' show TodayScreen;
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/school_screen.dart';

import 'activity_lists_test.dart' show ActivityFixture;
import 'field_layout_test.dart' show mountFields;
import 'support/calendar_results_fixture.dart';

class LongActivityFixture extends ActivityFixture {
  LongActivityFixture(String role) {
    token = 'synthetic-scroll-$role';
    snapshot!['user'] = {'id': role, 'name': 'Стёпа', 'role': role};
    snapshot!['tasks'] = <Map<String, dynamic>>[];
    snapshot!['ledger'] = [
      for (var i = 0; i < 180; i++)
        {
          'id': 'entry-$i',
          'actual': i == 0 ? -5 : 5,
          'requested': i == 0 ? -10 : 5,
          'reason': 'Запись $i',
          'created_at': '2026-10-14T20:53:20Z',
        },
    ];
    snapshot!['rewards'] = [
      for (var i = 0; i < 25; i++)
        {
          'id': 'reward-$i',
          'title': 'Награда $i',
          'description': '',
          'price': 50,
          'available': 1,
        },
    ];
    snapshot!['redemptions'] = [
      for (var i = 0; i < 80; i++)
        {
          'id': 'request-$i',
          'title': 'Заявка $i',
          'amount': 50,
          'status': 'confirmed',
        },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> pending() async => [
    for (var i = 0; i < 120; i++)
      {'id': 'pending-$i', 'error': 'Ошибка записи $i'},
  ];
}

Finder sectionScroll(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(Scrollable),
);

Future<void> scrollSectionTo(
  WidgetTester tester,
  String key,
  Finder target,
) async {
  await revealSection(tester, key);
  await tester.scrollUntilVisible(
    target,
    1000,
    scrollable: sectionScroll(key),
    maxScrolls: 260,
  );
  await tester.pumpAndSettle();
  expect(target, findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> revealSection(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  final root = find.byType(Scrollable).first;
  if (target.evaluate().isEmpty) {
    tester.state<ScrollableState>(root).position.jumpTo(0);
    await tester.pump();
    // Drag the page's margin, leaving nested lists free to handle their own gestures.
    for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
      final rect = tester.getRect(root);
      await tester.dragFrom(
        Offset(rect.left + 4, rect.center.dy),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
    }
  }
  expect(target, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}

void main() {
  for (final role in ['child', 'parent']) {
    testWidgets(
      '$role can scroll all 180 coin entries and other money sections',
      (tester) async {
        final repo = LongActivityFixture(role);
        addTearDown(() {
          repo.client.close();
          repo.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await mountFields(
          tester,
          Scaffold(
            body: MoneyScreen(
              repository: repo,
              perform: (_) async => fail('Reading must not change coins'),
            ),
          ),
          child: role == 'child',
          scale: 1.6,
        );
        await revealSection(tester, 'money-ledger');
        final historyTop = tester.getTopLeft(
          find.byKey(const ValueKey('money-ledger')),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('money-ledger'))).height,
          lessThanOrEqualTo(320),
        );
        expect(find.byKey(const ValueKey('ledger-entry-179')), findsOneWidget);
        expect(find.byKey(const ValueKey('ledger-entry-0')), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('ledger-entry-0')),
          1000,
          scrollable: sectionScroll('money-ledger'),
          maxScrolls: 260,
        );
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('money-ledger'))),
          historyTop,
        );
        expect(find.text('-5 · Запись 0'), findsOneWidget);
        expect(
          find.text('14.10.2026 23:53 · назначено -10, применено -5'),
          findsOneWidget,
        );
        expect(find.textContaining('2026-10-14T'), findsNothing);
        await scrollSectionTo(
          tester,
          'money-requests',
          find.byKey(const ValueKey('redemption-request-0')),
        );
        await scrollSectionTo(
          tester,
          'money-rewards',
          find.byKey(const ValueKey('reward-reward-24')),
        );
        expect(repo.changes, isEmpty);
      },
    );

    testWidgets('$role can read all queued errors without growing the page', (
      tester,
    ) async {
      final repo = LongActivityFixture(role);
      addTearDown(() {
        repo.client.close();
        repo.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await mountFields(
        tester,
        Scaffold(
          body: role == 'child'
              ? ChildToday(repository: repo, openPage: (_) {})
              : TodayScreen(repository: repo, openPage: (_) {}),
        ),
        child: role == 'child',
        scale: 1.6,
      );
      await tester.pumpAndSettle();
      await scrollSectionTo(
        tester,
        'pending-activities',
        find.text('Ошибка записи 119'),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('pending-activities'))).height,
        lessThanOrEqualTo(320),
      );
    });
  }

  testWidgets(
    'short lists collapse and session changes reset long-list position',
    (tester) async {
      Widget screen(int count, String identity) => Scaffold(
        body: ListView(
          children: [
            ActivityWindow(
              key: const ValueKey('window'),
              count: count,
              filterKey: identity,
              compactWhenShort: true,
              showCount: false,
              emptyText: 'Пусто',
              itemBuilder: (_, i) => ListTile(title: Text('Элемент $i')),
            ),
            const Text('Следующий раздел'),
          ],
        ),
      );
      await mountFields(tester, screen(120, 'first'), scale: 1);
      await scrollSectionTo(tester, 'window', find.text('Элемент 119'));
      await mountFields(tester, screen(120, 'second'), scale: 1);
      expect(find.text('Элемент 0'), findsOneWidget);
      await mountFields(tester, screen(1, 'second'), scale: 1);
      expect(sectionScroll('window'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('window'))).height,
        lessThan(100),
      );
      await mountFields(tester, screen(0, 'second'), scale: 1);
      expect(find.text('Пусто'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('all 100 preserved grades remain reachable', (tester) async {
    final repo = ResultsFixture(role: 'child');
    repo.snapshot!['schedules'] = <Map<String, dynamic>>[];
    repo.snapshot!['tasks'] = <Map<String, dynamic>>[];
    repo.snapshot!['grades'] = [
      for (var i = 0; i < 100; i++)
        {
          'id': 'grade-$i',
          'date': '2026-10-12',
          'subject_id': 'old-subject',
          'grade': 5,
          'note': 'Оценка $i',
        },
    ];
    addTearDown(() {
      repo.client.close();
      repo.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await mountFields(
      tester,
      Scaffold(
        body: SchoolScreen(
          repository: repo,
          perform: (_) async => fail('Reading cannot save a grade'),
          initialDay: DateTime(2026, 10, 12),
        ),
      ),
      child: true,
      scale: 1.6,
    );
    final lastGrade = find.byKey(const ValueKey('result-history-grade-99'));
    expect(find.byType(Scrollable), findsOneWidget);
    await tester.scrollUntilVisible(
      lastGrade,
      1000,
      scrollable: find.byType(Scrollable),
      maxScrolls: 260,
    );
    await tester.ensureVisible(lastGrade);
    await tester.pumpAndSettle();
    expect(lastGrade.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(repo.changes, isEmpty);
  });
}
