import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/schedule.dart';

import 'calendar_navigation_test.dart' show mountCalendar, tapVisible;
import 'field_layout_test.dart' show revealField;
import 'support/calendar_results_fixture.dart';

ResultsFixture entriesFor(String role, DateTime selected) {
  final repo = ResultsFixture(role: role);
  repo.snapshot!['tasks'] = <Map<String, dynamic>>[];
  repo.snapshot!['schedules'] = [
    for (final id in ['other', 'chosen'])
      {
        ...ResultsFixture.schoolEvent(),
        'id': id,
        'title': 'Одинаковые события',
        'weekdays': '[1,2,3,4,5,6,7]',
        'start': id == 'chosen' ? '14:00' : '09:00',
        'end': id == 'chosen' ? '16:00' : '11:00',
        'activities': jsonEncode([
          {
            'id': mathIdentity,
            'title': 'Математика',
            'start': id == 'chosen' ? '14:00' : '09:00',
            'end': id == 'chosen' ? '16:00' : '11:00',
          },
        ]),
      },
  ];
  repo.snapshot!['schedule_exceptions'] = [
    {
      'schedule_id': 'chosen',
      'date': dateOnly(selected),
      'replacement': jsonEncode({
        'start': '15:00',
        'note': 'Именно эта запись за ${dateOnly(selected)}',
        'activities': [
          {
            'id': mathIdentity,
            'title': 'Математика',
            'start': '15:00',
            'end': '16:00',
          },
        ],
      }),
    },
  ];
  return repo;
}

void main() {
  for (final role in ['parent', 'child', 'relative']) {
    for (final view in ['День', 'Неделя', 'Месяц']) {
      for (final number in [16, 20]) {
        testWidgets(
          '$role $view event opens exact occurrence on October $number',
          (tester) async {
            final selected = DateTime.utc(2026, 10, number, 12);
            final repo = entriesFor(role, selected);
            // In Week the clicked event belongs to a different day from the
            // initially selected one; other occurrences have the same title.
            await mountCalendar(
              tester,
              repo,
              day: view == 'Неделя'
                  ? selected.subtract(const Duration(days: 1))
                  : selected,
            );
            await tester.tap(find.widgetWithText(ChoiceChip, view));
            await tester.pumpAndSettle();
            if (view == 'Месяц') {
              await tapVisible(
                tester,
                find.byWidgetPredicate(
                  (widget) =>
                      widget is CalendarTile &&
                      widget.entry.source?['id'] == 'chosen',
                ),
              );
            } else {
              final event = find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.label ==
                        'Одинаковые события, 15:00 — 16:00, занятий 1',
              );
              await tester.ensureVisible(event);
              await tester.pumpAndSettle();
              await tester.tap(
                find.descendant(of: event, matching: find.byType(InkWell)),
              );
              await tester.pumpAndSettle();
            }
            final detail = tester.widget<CalendarTile>(
              find.descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(CalendarTile),
              ),
            );
            expect(detail.entry.source?['id'], 'chosen');
            expect(dateOnly(detail.entry.start), dateOnly(selected));
            expect(detail.entry.timeText, '15:00 — 16:00');
            expect(
              detail.entry.note,
              'Именно эта запись за ${dateOnly(selected)}',
            );
            expect(detail.entry.activities.single.start, '15:00');
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            await tapVisible(tester, find.text('Предметы и оценки'));
            expect(find.text(calendarDateLabel(selected)), findsOneWidget);
            expect(
              find.byKey(
                ValueKey(
                  'result-schedule:chosen:${dateOnly(selected)}:$mathIdentity',
                ),
              ),
              findsOneWidget,
            );
            expect(repo.changes, isEmpty);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  for (final view in ['День', 'Неделя', 'Месяц']) {
    for (final number in [16, 20]) {
      testWidgets('$view grade edit targets exact record on October $number', (
        tester,
      ) async {
        final selected = DateTime.utc(2026, 10, number, 12);
        final repo = entriesFor('parent', selected);
        repo.snapshot!['grades'] = [
          for (final day in [16, 17, 20])
            for (final schedule in ['chosen', 'other'])
              {
                'id': '$schedule-$day',
                'schedule_id': schedule,
                'activity_id': mathIdentity,
                'date': '2026-10-$day',
                'grade': 4,
                'revision': '$schedule-$day-revision',
                'note': 'Запись $schedule за $day октября',
              },
        ];
        await mountCalendar(tester, repo, day: selected);
        await tester.tap(find.widgetWithText(ChoiceChip, view));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Предметы и оценки'));
        await tapVisible(
          tester,
          find.byKey(
            ValueKey(
              'result-grade-schedule:chosen:${dateOnly(selected)}:$mathIdentity',
            ),
          ),
        );
        expect(find.text('Исправить оценку: Математика'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
          'Запись chosen за $number октября',
        );
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('5').last);
        await tester.pumpAndSettle();
        await revealField(tester, find.text('Сохранить'));
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        final change = repo.changes.single;
        expect(change['method'], 'PUT');
        expect(change['path'], '/v1/grades/chosen-$number');
        expect(change['body'], {
          'schedule_id': 'chosen',
          'activity_id': mathIdentity,
          'date': dateOnly(selected),
          'grade': 5,
          'note': 'Запись chosen за $number октября',
          'expected_revision': 'chosen-$number-revision',
        });
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Предметы и оценки'));
        expect(find.text(calendarDateLabel(selected)), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
