import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';

Map<String, dynamic> event(
  String id,
  String start,
  String end, {
  String kind = 'school',
}) => {
  'id': id,
  'title': id,
  'date': '2026-10-12',
  'weekdays': '[]',
  'start': start,
  'end': end,
  'kind': kind,
  'reminder_minutes': 30,
  'active': 1,
};
Map<String, dynamic> snapshot(List<Map<String, dynamic>> schedules) => {
  'family': {
    'timezone': 'Europe/Moscow',
    'quiet_start': '21:00',
    'quiet_end': '08:00',
    'day_start': '07:00',
    'day_end': '22:00',
  },
  'schedules': schedules,
  'tasks': <Map<String, dynamic>>[],
  'schedule_exceptions': <Map<String, dynamic>>[],
};
void main() {
  final date = DateTime.utc(2026, 10, 12, 12);
  test('calendar contains real events only; free time is not generated', () {
    final data = snapshot([
      event('school', '08:30', '14:00'),
      event('chess', '13:00', '15:00', kind: 'extra'),
    ]);
    final entries = calendarDay(data, date);
    expect(entries.map((e) => e.title), ['school', 'chess']);
    expect(calendarConflicts(entries).length, 2);
    expect(calendarDay(snapshot([]), date), isEmpty);
    data['user'] = {'role': 'relative'};
    expect(calendarDay(data, date).length, 2);
  });
  test('weekly bounds, cancellation, replacement, archive, leap day', () {
    final row = {
      ...event('math', '08:30', '09:15'),
      'date': null,
      'weekdays': '[1]',
      'starts_on': '2026-10-12',
      'until': '2026-10-19',
    };
    final data = snapshot([row]);
    int count(DateTime day) => calendarDay(data, day).length;
    expect(count(DateTime.utc(2026, 10, 5, 12)), 0);
    expect(count(date), 1);
    expect(count(DateTime.utc(2026, 10, 19, 12)), 1);
    expect(count(DateTime.utc(2026, 10, 26, 12)), 0);
    data['schedule_exceptions'] = [
      {'schedule_id': 'math', 'date': '2026-10-12', 'replacement': null},
    ];
    expect(count(date), 0);
    data['schedule_exceptions'] = [
      {
        'schedule_id': 'math',
        'date': '2026-10-12',
        'replacement': jsonEncode({
          'title': 'Перенос',
          'start': '10:00',
          'end': '11:00',
          'reminder_minutes': null,
        }),
      },
    ];
    expect(calendarDay(data, date).single.timeText, '10:00 — 11:00');
    row['active'] = 0;
    expect(count(date), 0);
    data['schedules'] = [
      {...event('leap', '12:00', '13:00'), 'date': '2028-02-29'},
    ];
    expect(count(DateTime.utc(2028, 2, 29, 12)), 1);
    expect(count(DateTime.utc(2028, 3, 1, 12)), 0);
  });
  test(
    'planned tasks occupy time; deadline only tasks do not invent duration',
    () {
      final data = snapshot([]);
      data['tasks'] = [
        {
          'id': 'planned',
          'title': 'Домашняя работа',
          'status': 'assigned',
          'subject_id': 'math',
          'planned_start': '2026-10-12T16:30:00Z',
          'planned_end': '2026-10-12T17:30:00Z',
          'due_at': '2026-10-12T19:00:00Z',
          'reminder_minutes': 15,
        },
        {
          'id': 'deadline',
          'title': 'Задание',
          'status': 'returned',
          'due_at': '2026-10-12T18:00:00Z',
        },
        {
          'id': 'cancelled',
          'title': 'Отменено',
          'status': 'cancelled',
          'due_at': '2026-10-12T18:00:00Z',
        },
      ];
      final entries = calendarDay(data, date);
      expect(
        entries.firstWhere((e) => e.title == 'Домашняя работа').timeText,
        '19:30 — 20:30',
      );
      expect(entries.firstWhere((e) => e.deadline).timeText, 'До 21:00');
      expect(entries.length, 2);
    },
  );
  test('morning groups school, lists subjects, preserves other events without free time', () {
    final data = snapshot([
      event('Математика', '08:30', '09:15'),
      event('Литература', '09:25', '10:10'),
      event('Шахматы', '15:00', '16:00', kind: 'extra'),
    ]);
    final entries = morningEntries(calendarDay(data, date));
    final school = entries.firstWhere((e) => e.kind == 'school');
    expect(school.timeText, '08:30 — 10:10');
    expect(school.note, 'Математика, Литература');
    expect(entries.where((e) => e.kind == 'school').length, 1);
    expect(entries.length, 2);
    expect(morningEntries(calendarDay(snapshot([]), date)), isEmpty);
  });
  test(
    '30 minute default, customization, off, quiet time, stable IDs, exceptions',
    () {
      final data = snapshot([
        event('math', '08:30', '09:15'),
        {...event('music', '15:00', '16:00'), 'reminder_minutes': 60},
        {...event('off', '16:00', '17:00'), 'reminder_minutes': null},
        event('quiet', '21:30', '22:00'),
        event('planned-break', '18:00', '19:00', kind: 'free'),
      ]);
      final now = DateTime.utc(2026, 10, 12, 4);
      final plan = calendarReminders(data, now);
      expect(plan.map((r) => clockText(r.at)), ['08:00', '14:00', '17:30']);
      expect(plan.first.payload, 'calendar:2026-10-12');
      expect(
        calendarReminders(
          data,
          now.add(const Duration(minutes: 1)),
        ).map((r) => r.id),
        plan.map((r) => r.id),
      );
      data['schedule_exceptions'] = [
        {'schedule_id': 'math', 'date': '2026-10-12', 'replacement': null},
      ];
      expect(calendarReminders(data, now).length, 2);
    },
  );
  test(
    'Amsterdam daylight saving uses local dates and local lesson clocks',
    () {
      final data = snapshot([
        {...event('DST', '08:30', '09:15'), 'date': null, 'weekdays': '[7]'},
      ]);
      data['family']['timezone'] = 'Europe/Amsterdam';
      data['family']['quiet_start'] = '00:00';
      data['family']['quiet_end'] = '00:00';
      final before = calendarReminders(data, DateTime.utc(2026, 10, 24, 23));
      expect(clockText(before.first.at), '08:00');
      expect(before.first.at.timeZoneOffset, const Duration(hours: 1));
    },
  );
}
