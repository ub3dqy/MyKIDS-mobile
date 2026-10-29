import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/calendar_grid.dart';
import 'package:mykids_family/schedule.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar_test.dart' as fixture;
import 'field_layout_test.dart' show mountFields;

void main() {
  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> data, {
    double scale = 1,
    bool week = false,
  }) async {
    final day = familyClock(data, DateTime.utc(2026, 10, 12, 12));
    await mountFields(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CalendarTimeline(
            days: [
              day,
              if (week)
                tz.TZDateTime(day.location, day.year, day.month, day.day + 1),
            ],
            entries: (value) => calendarDay(data, value),
            open: (_) {},
          ),
        ),
      ),
      scale: scale,
    );
  }

  void reset(WidgetTester tester) {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder cell(int hour, {String date = '2026-10-12'}) =>
      find.byKey(ValueKey('calendar-cell-$date-$hour'));

  testWidgets('empty grid renders all 25 boundaries and compact rows', (
    tester,
  ) async {
    reset(tester);
    await mount(tester, fixture.snapshot([]));
    for (var hour = 0; hour <= 24; hour++) {
      expect(find.byKey(ValueKey('calendar-hour-$hour')), findsOneWidget);
    }
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('24:00'), findsOneWidget);
    expect(tester.getSize(cell(0)).height, lessThanOrEqualTo(32));
    expect(tester.getSize(cell(23)).height, lessThanOrEqualTo(32));
    expect(
      find.byKey(const ValueKey('calendar-day-end-2026-10-12')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('short event fits all wrapped text at font scale $scale', (
      tester,
    ) async {
      reset(tester);
      const title =
          'Подготовка к занятиям и проверка всех школьных принадлежностей';
      const note =
          'Взять тетради, учебники, альбом и сменную обувь. Проверить расписание вместе с родителями.';
      const subject = 'Изобразительное искусство и художественный труд';
      final data = fixture.snapshot([
        {
          ...fixture.event(title, '09:05', '09:15'),
          'note': note,
          'activities': [
            {'title': subject, 'start': '09:05', 'end': '09:15'},
          ],
        },
      ]);
      await mount(tester, data, scale: scale);
      final block = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label ?? '').startsWith('$title,'),
      );
      final box = tester.getRect(block);
      for (final text in [title, note, subject, '09:05 — 09:15']) {
        for (final element in find.text(text).evaluate()) {
          final bounds =
              (element.renderObject! as RenderBox).localToGlobal(Offset.zero) &
              (element.renderObject! as RenderBox).size;
          expect(bounds.top, greaterThanOrEqualTo(box.top));
          expect(bounds.bottom, lessThanOrEqualTo(box.bottom + 1));
          expect(bounds.right, lessThanOrEqualTo(box.right + 1));
        }
      }
      expect(
        tester.getSize(cell(9)).height,
        greaterThan(tester.getSize(cell(8)).height),
      );
      expect(tester.getSize(cell(10)).height, lessThanOrEqualTo(40));
      expect(
        tester.getSize(cell(10)).height,
        closeTo(tester.getSize(cell(8)).height, .001),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'weekly days share expanded coordinates and react to larger text',
    (tester) async {
      reset(tester);
      final data = fixture.snapshot([
        {
          ...fixture.event('Школа', '09:00', '14:00'),
          'activities': [
            for (var i = 9; i < 14; i++)
              {
                'title': 'Занятие с подробным названием предмета',
                'start': '${i.toString().padLeft(2, '0')}:00',
                'end': '${(i + 1).toString().padLeft(2, '0')}:00',
              },
          ],
        },
      ]);
      await mount(tester, data, week: true);
      final normal = tester.getSize(cell(9)).height;
      await mount(tester, data, scale: 2, week: true);
      expect(tester.getSize(cell(9)).height, greaterThan(normal));
      expect(
        tester.getRect(cell(14)).top,
        closeTo(tester.getRect(cell(14, date: '2026-10-13')).top, .001),
      );
      expect(
        tester.getSize(cell(9, date: '2026-10-13')).height,
        closeTo(tester.getSize(cell(9)).height, .001),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
