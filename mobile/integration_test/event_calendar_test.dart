import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';

import '../test/calendar_test.dart' as fixture;
import '../test/event_blocks_test.dart' show schoolBlock, revealEvent;
import '../test/field_layout_test.dart' show mountFields;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('calendar blocks, views and simple editor on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    Future<void> capture(String name) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await binding.takeScreenshot('calendar-$name');
    }

    for (final role in ['parent', 'child', 'relative']) {
      final repo = FamilyRepository()
        ..variant = role
        ..online = true
        ..endpoint = 'https://family.example';
      repo.snapshot = fixture.snapshot([
        schoolBlock(),
        fixture.event('Плавание', '17:00', '18:00', kind: 'extra'),
      ])..['user'] = {'id': role, 'role': role, 'name': role};
      await mountFields(
        tester,
        Scaffold(
          body: CalendarScreen(
            repository: repo,
            initialDay: DateTime.utc(2026, 10, 12, 12),
            perform: (action) async {
              await action();
            },
            openTasks: (_) {},
          ),
        ),
        screenSize: null,
        scale: 1.2,
      );
      await revealEvent(tester, find.text('Школа'));
      expect(find.text('Русский язык'), findsOneWidget);
      expect(find.text('Свободное время'), findsNothing);
      await capture('$role-day');
      await tester.tap(find.text('Школа'));
      await tester.pumpAndSettle();
      expect(
        find.text('Изменить событие'),
        role == 'parent' ? findsOneWidget : findsNothing,
      );
      await capture('$role-details');
      Navigator.of(tester.element(find.byType(CalendarTile))).pop();
      await tester.pumpAndSettle();
      if (role == 'parent') {
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, 10000),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Неделя'));
        await tester.pumpAndSettle();
        await revealEvent(tester, find.text('Школа'));
        await capture('week');
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, 10000),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
        await tester.pumpAndSettle();
        await revealEvent(
          tester,
          find.byKey(const ValueKey('calendar-day-2026-10-12')),
        );
        await capture('month');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    }
    final data = fixture.snapshot([]);
    await mountFields(
      tester,
      CalendarEditor(
        snapshot: data,
        initial: schoolBlock(),
        day: familyClock(data, DateTime.utc(2026, 10, 12, 12)),
      ),
      screenSize: null,
      scale: 2,
    );
    await capture('editor-top-large');
    await revealEvent(tester, find.byKey(const ValueKey('activity-title-0')));
    await capture('editor-lessons-large');
    expect(tester.takeException(), isNull);
    binding.reportData = {
      ...?binding.reportData,
      'synthetic_only': true,
      'roles_checked': 3,
      'views_checked': ['day', 'week', 'month'],
      'nested_lessons_checked': true,
      'editor_text_scale': 2,
      'physical_phone_tested': false,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
