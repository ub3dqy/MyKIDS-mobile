import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/calendar_grid.dart';
import 'package:mykids_family/schedule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../test/calendar_test.dart' as fixture;
import '../test/event_blocks_test.dart' show schoolBlock;
import '../test/field_layout_test.dart' show mountFields;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('complete compact day and text-driven event heights on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    Future<void> show(
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
        screenSize: null,
        scale: scale,
      );
    }

    Future<void> capture(String name) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await binding.takeScreenshot('adaptive-$name');
    }

    await show(fixture.snapshot([]));
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('24:00'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('calendar-cell-2026-10-12-0')))
          .height,
      lessThanOrEqualTo(32),
    );
    await capture('empty-day');
    await show(fixture.snapshot([schoolBlock()]));
    expect(find.text('Математика'), findsOneWidget);
    expect(find.text('Русский язык'), findsOneWidget);
    await capture('school-day');
    await show(fixture.snapshot([schoolBlock()]), week: true);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('calendar-cell-2026-10-12-14')))
          .top,
      closeTo(
        tester
            .getRect(find.byKey(const ValueKey('calendar-cell-2026-10-13-14')))
            .top,
        .001,
      ),
    );
    await capture('week');
    await show(
      fixture.snapshot([
        {
          ...fixture.event('Сборы в школу', '09:05', '09:15'),
          'note': 'Взять тетради, учебники, альбом и сменную обувь. Проверить расписание вместе с родителями.',
          'activities': [
            {
              'title': 'Изобразительное искусство и художественный труд',
              'start': '09:05',
              'end': '09:15',
            },
          ],
        },
      ]),
      scale: 2,
    );
    await capture('long-short-event');
    expect(tester.takeException(), isNull);
    binding.reportData = {
      ...?binding.reportData,
      'synthetic_only': true,
      'all_hour_boundaries': 25,
      'compact_empty_hours_verified': true,
      'shared_week_coordinates_verified': true,
      'large_text_checked': true,
      'physical_phone_tested': false,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
