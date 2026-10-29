import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/school_screen.dart';

import 'field_layout_test.dart' show mountFields, revealField;
import 'support/calendar_results_fixture.dart';

Map<String, dynamic> saved(int amount) => {
  'id': 'saved',
  'subject_id': 'old-subject',
  'date': '2026-10-12',
  'grade': 4,
  'note': 'Запись',
  'revision': 'a' * 64,
  'posted_amount': amount,
};

Future<ResultsFixture> mount(
  WidgetTester tester, {
  int amount = 25,
  String role = 'parent',
}) async {
  final repo = ResultsFixture(role: role);
  addTearDown(() {
    repo.client.close();
    repo.dispose();
  });
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  repo.snapshot!['schedules'] = [];
  repo.snapshot!['tasks'] = [];
  repo.snapshot!['grades'] = [saved(amount)];
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
    scale: 1.5,
  );
  return repo;
}

Future<void> openDelete(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('result-delete-grade-saved'));
  await revealField(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final amount in [25, -40, 0]) {
    testWidgets('delete confirms actual posted coins once: $amount', (
      tester,
    ) async {
      final repo = await mount(tester, amount: amount);
      await openDelete(tester);
      expect(
        find.textContaining(
          amount > 0
              ? 'спишутся'
              : amount < 0
              ? 'вернутся'
              : 'не начислялись',
        ),
        findsOneWidget,
      );
      final confirm = find.byKey(const ValueKey('confirm-delete-grade'));
      await revealField(tester, confirm);
      final press = tester.widget<FilledButton>(confirm).onPressed!;
      press();
      press();
      await tester.pumpAndSettle();
      expect(repo.changes, hasLength(1));
      expect(repo.changes.single['method'], 'DELETE');
      expect(repo.changes.single['path'], '/v1/grades/saved');
      expect(repo.changes.single['body'], {
        'expected_revision': 'a' * 64,
        'expected_posted': amount,
      });
      expect(find.byType(SchoolScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('delete cancellation leaves the grade untouched', (tester) async {
    final repo = await mount(tester);
    await openDelete(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(repo.rows('grades'), hasLength(1));
  });

  for (final change in [
    'account',
    'generation',
    'endpoint',
    'role',
    'revision',
    'coins',
    'removed',
  ]) {
    testWidgets('an open deletion cannot act after $change changes', (
      tester,
    ) async {
      final repo = await mount(tester);
      await openDelete(tester);
      final confirm = find.byKey(const ValueKey('confirm-delete-grade'));
      final oldPress = tester.widget<FilledButton>(confirm).onPressed!;
      switch (change) {
        case 'account':
          repo.token = 'other';
        case 'generation':
          repo.generation++;
        case 'endpoint':
          repo.endpoint = 'https://other.example';
        case 'role':
          repo.snapshot!['user']['role'] = 'child';
        case 'revision':
          repo.snapshot!['grades'][0]['revision'] = 'b' * 64;
        case 'coins':
          repo.snapshot!['grades'][0]['posted_amount'] = 10;
        case 'removed':
          repo.snapshot!['grades'] = [];
      }
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      oldPress();
      await tester.pumpAndSettle();
      expect(repo.changes, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an old edit form cannot save into a new account', (
    tester,
  ) async {
    final repo = await mount(tester);
    final edit = find.byKey(const ValueKey('result-edit-grade-saved'));
    await revealField(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    repo.token = 'other';
    repo.notifyListeners();
    final save = find.text('Сохранить');
    await revealField(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(find.byType(FamilyForm), findsOneWidget);
    expect(find.textContaining('Семейный доступ изменился'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final role in ['child', 'relative']) {
    testWidgets('$role cannot delete or edit a grade', (tester) async {
      await mount(tester, role: role);
      expect(
        find.byKey(const ValueKey('result-delete-grade-saved')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('result-edit-grade-saved')),
        findsNothing,
      );
    });
  }
}
