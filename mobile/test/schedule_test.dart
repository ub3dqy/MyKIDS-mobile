import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/schedule.dart';

void main() {
  final schedules = <Map<String, dynamic>>[
    {
      'id': 'math',
      'title': 'Математика',
      'date': null,
      'weekdays': '[1,3]',
      'start': '09:00',
      'end': '09:40',
    },
    {
      'id': 'music',
      'title': 'Музыка',
      'date': '2026-10-12',
      'weekdays': '[]',
      'start': '15:00',
      'end': '16:00',
    },
  ];
  test(
    'cancelling one lesson does not cancel the following weekly occurrence',
    () {
      final exceptions = <Map<String, dynamic>>[
        {'schedule_id': 'math', 'date': '2026-10-12', 'replacement': null},
      ];
      expect(
        daySchedule(
          schedules,
          exceptions,
          DateTime(2026, 10, 12),
        ).map((l) => l['title']),
        ['Музыка'],
      );
      expect(
        daySchedule(
          schedules,
          exceptions,
          DateTime(2026, 10, 14),
        ).map((l) => l['title']),
        ['Математика'],
      );
    },
  );
  test('single replacement preserves chronology', () {
    final exceptions = <Map<String, dynamic>>[
      {
        'schedule_id': 'math',
        'date': '2026-10-12',
        'replacement':
            '{"title":"Перенос математики","start":"17:00","end":"17:40"}',
      },
    ];
    expect(
      daySchedule(
        schedules,
        exceptions,
        DateTime(2026, 10, 12),
      ).map((l) => l['title']),
      ['Музыка', 'Перенос математики'],
    );
    expect(
      daySchedule(schedules, exceptions, DateTime(2026, 10, 12)).last['id'],
      'math',
    );
  });

  test(
    'family day follows configured timezone rather than phone or server',
    () {
      final clock = familyClock({
        'family': {'timezone': 'Europe/Moscow'},
      }, DateTime.utc(2026, 10, 11, 22));
      expect(dateOnly(clock), '2026-10-12');
      expect(clock.hour, 1);
    },
  );
}
