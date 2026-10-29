import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/morning.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/visuals.dart';

import 'calendar_test.dart' as fixture;

void main() {
  Future<void> size(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('ru')],
        theme: familyTheme(true),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  for (final role in ['child', 'parent', 'relative']) {
    testWidgets('calendar all periods at 320px and doubled text: $role', (
      tester,
    ) async {
      final repo = FamilyRepository()
        ..variant = role
        ..online = true;
      repo.snapshot = fixture.snapshot([
        fixture.event('Математика', '08:30', '14:00'),
        fixture.event('Шахматы', '15:00', '16:00', kind: 'extra'),
      ]);
      repo.snapshot!['user'] = {'id': role, 'role': role, 'name': role};
      await size(
        tester,
        CalendarScreen(
          repository: repo,
          initialDay: DateTime.utc(2026, 10, 12, 12),
          perform: (action) async {
            await action();
          },
          openTasks: (_) {},
        ),
      );
      for (final view in ['День', 'Неделя', 'Месяц']) {
        await tester.tap(find.widgetWithText(ChoiceChip, view));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final scroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Семейные задания'),
          400,
          scrollable: scroll,
        );
        expect(tester.takeException(), isNull);
        await tester.drag(scroll, const Offset(0, 10000));
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
  testWidgets('morning next and whole day at large text size', (tester) async {
    final data = fixture.snapshot([
      fixture.event('Математика', '08:30', '14:00'),
      fixture.event('Шахматы', '15:00', '16:00', kind: 'extra'),
    ]);
    await size(
      tester,
      MorningOverview(
        entries: morningEntries(
          calendarDay(data, DateTime.utc(2026, 10, 12, 12)),
        ),
        dayLabel: '12.10',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Дальше'), findsOneWidget);
    await tester.tap(find.text('Дальше'));
    await tester.pump();
    expect(find.text('15:00 — 16:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('changing family timezone preserves the selected calendar day', (
    tester,
  ) async {
    final repo = FamilyRepository()..variant = 'parent';
    repo.snapshot = fixture.snapshot([
      fixture.event('Математика', '08:30', '14:00'),
    ])..['user'] = {'id': 'parent', 'role': 'parent', 'name': 'Папа'};
    final selected = DateTime.utc(2026, 10, 12, 12);
    Widget screen() => CalendarScreen(
      repository: repo,
      initialDay: selected,
      perform: (action) async {
        await action();
      },
      openTasks: (_) {},
    );
    await size(tester, screen());
    await tester.scrollUntilVisible(
      find.text('Математика'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Математика'), findsOneWidget);
    repo.snapshot!['family']['timezone'] = 'Europe/Amsterdam';
    await size(tester, screen());
    await tester.scrollUntilVisible(
      find.text('Математика'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Математика'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('calendar editor validates time and weekday fields', (
    tester,
  ) async {
    final data = fixture.snapshot([]);
    await size(
      tester,
      CalendarEditor(
        snapshot: data,
        day: familyClock(data, DateTime.utc(2026, 10, 12, 12)),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Сохранить'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 10000));
    await tester.pump();
    expect(find.text('Введите название'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
