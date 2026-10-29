import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/repository.dart';

import 'calendar_test.dart' as fixture;
import 'field_layout_test.dart' show mountFields, revealField;

class LiveEventFixture extends FamilyRepository {
  LiveEventFixture(String role) {
    token = 'synthetic-calendar-session';
    endpoint = 'https://family.example';
    online = true;
    snapshot = fixture.snapshot([fixture.event('Прогулка', '12:00', '13:00')])
      ..['user'] = {'id': role, 'name': role, 'role': role};
  }
  void change(Map<String, dynamic>? row) {
    snapshot!['schedules'] = row == null ? <Map<String, dynamic>>[] : [row];
    notifyListeners();
  }

  void switchSession() {
    token = 'another-synthetic-session';
    generation++;
    change({
      ...fixture.event('Прогулка', '12:00', '13:00'),
      'title': 'Другая семья',
    });
  }
}

Future<LiveEventFixture> openEvent(WidgetTester tester, String role) async {
  final repo = LiveEventFixture(role);
  addTearDown(() {
    repo.client.close();
    repo.dispose();
  });
  await mountFields(
    tester,
    Scaffold(
      body: AnimatedBuilder(
        animation: repo,
        builder: (_, _) => CalendarScreen(
          repository: repo,
          initialDay: DateTime.utc(2026, 10, 12, 12),
          perform: (_) async => fail('Viewing must not save changes'),
          openTasks: (_) {},
        ),
      ),
    ),
    scale: 1.2,
  );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await revealField(tester, find.text('Прогулка'));
  await tester.tap(find.text('Прогулка'));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
  return repo;
}

Finder inSheet(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

void main() {
  for (final role in ['parent', 'child', 'relative']) {
    testWidgets('open event details refresh name time and place for $role', (
      tester,
    ) async {
      final repo = await openEvent(tester, role);
      repo.change({
        ...fixture.event('Прогулка', '14:00', '15:00'),
        'title': 'Прогулка у реки',
        'note': 'Возьми воду',
        'place': 'Набережная',
      });
      await tester.pumpAndSettle();
      expect(inSheet('Прогулка у реки'), findsOneWidget);
      expect(inSheet('14:00 — 15:00'), findsOneWidget);
      expect(inSheet('Возьми воду'), findsOneWidget);
      expect(inSheet('Набережная'), findsOneWidget);
      expect(inSheet('Прогулка'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('cancelled event disappears from open details for $role', (
      tester,
    ) async {
      final repo = await openEvent(tester, role);
      repo.change(null);
      await tester.pumpAndSettle();
      expect(
        inSheet('На этот день событие отменено или перенесено'),
        findsOneWidget,
      );
      expect(inSheet('Прогулка'), findsNothing);
      expect(inSheet('Изменить событие'), findsNothing);
      await tester.tap(inSheet('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Прогулка'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('session switch clears old event details for $role', (
      tester,
    ) async {
      final repo = await openEvent(tester, role);
      repo.switchSession();
      await tester.pumpAndSettle();
      expect(inSheet('Прогулка'), findsNothing);
      expect(inSheet('Другая семья'), findsNothing);
      expect(inSheet('Нужно открыть окно заново'), findsOneWidget);
      expect(inSheet('Изменить событие'), findsNothing);
      await tester.tap(inSheet('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('event repeat controls reflect current repeat settings', (
    tester,
  ) async {
    final repo = await openEvent(tester, 'parent');
    repo.change({
      ...fixture.event('Прогулка', '12:00', '13:00'),
      'date': null,
      'weekdays': '[1]',
    });
    await tester.pumpAndSettle();
    expect(inSheet('Изменить только этот день'), findsOneWidget);
    expect(inSheet('Удалить событие и повторения'), findsOneWidget);
    repo.change(fixture.event('Прогулка', '12:00', '13:00'));
    await tester.pumpAndSettle();
    expect(inSheet('Изменить только этот день'), findsNothing);
    expect(inSheet('Удалить событие'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'external cancellation disables an already open delete confirmation',
    (tester) async {
      final repo = await openEvent(tester, 'parent');
      await tester.tap(inSheet('Удалить событие'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      repo.change(null);
      await tester.pumpAndSettle();
      expect(find.text('Событие уже отменено или перенесено'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Подтвердить'),
      );
      expect(confirm.onPressed, isNull);
      await tester.tap(find.text('Назад'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
