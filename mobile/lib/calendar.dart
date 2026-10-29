import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as tz;

import 'schedule.dart';
import 'task_rules.dart';
import 'assistant_rules.dart';

const calendarKinds = {
  'school': 'Школа',
  'extra': 'Дополнительное занятие',
  'homework': 'Домашняя работа',
  'task': 'Семейное задание',
  'free': 'Свободное время',
  'other': 'Важное событие',
};

const calendarWeekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
String calendarDateLabel(DateTime day) =>
    '${calendarWeekdays[day.weekday - 1]}, ${day.day}.${day.month.toString().padLeft(2, '0')}.${day.year}';

bool schoolSubjects(Map<String, dynamic> row) => row['grade_subjects'] != null
    ? row['grade_subjects'] == true || row['grade_subjects'] == 1
    : row['kind'] == 'school' ||
          row['subject_id'] != null ||
          schoolBlockTitle(row['title'] as String? ?? '');

bool schoolBlockTitle(String title) =>
    RegExp(r'^школа(?:\s|$)', caseSensitive: false).hasMatch(title.trim());

class CalendarActivity {
  final String title, start, end;
  final String? id;
  const CalendarActivity({
    required this.title,
    required this.start,
    required this.end,
    this.id,
  });
}

List<CalendarActivity> calendarActivities(dynamic value) {
  final rows = value is String ? jsonDecode(value) : value;
  return [
    for (final row in rows as List? ?? [])
      CalendarActivity(
        id: row['id'] as String?,
        title: row['title'] as String,
        start: row['start'] as String,
        end: row['end'] as String,
      ),
  ];
}

String clockText(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

class CalendarEntry {
  final String key, title, kind, note, place;
  final tz.TZDateTime start, end;
  final int? reminder;
  final Map<String, dynamic>? source;
  final bool deadline;
  final String? color;
  final List<CalendarActivity> activities;
  const CalendarEntry({
    required this.key,
    required this.title,
    required this.kind,
    required this.start,
    required this.end,
    this.note = '',
    this.place = '',
    this.reminder,
    this.source,
    this.deadline = false,
    this.color,
    this.activities = const [],
  });
  String get timeText => deadline
      ? 'До ${clockText(start)}'
      : '${clockText(start)} — ${clockText(end)}';
}

List<Map<String, dynamic>> calendarRows(
  Map<String, dynamic> snapshot,
  String key,
) => (snapshot[key] as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

tz.TZDateTime calendarTime(tz.TZDateTime day, String clock) {
  final parts = clock.split(':');
  return tz.TZDateTime(
    day.location,
    day.year,
    day.month,
    day.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );
}

List<CalendarEntry> calendarDay(Map<String, dynamic> snapshot, DateTime date) {
  final local = familyClock(snapshot, date);
  final day = tz.TZDateTime(local.location, local.year, local.month, local.day);
  final tomorrow = tz.TZDateTime(
    local.location,
    day.year,
    day.month,
    day.day + 1,
  );
  final entries = <CalendarEntry>[];
  for (final row in daySchedule(
    calendarRows(snapshot, 'schedules'),
    calendarRows(snapshot, 'schedule_exceptions'),
    day,
  )) {
    entries.add(
      CalendarEntry(
        key: 'schedule:${row['id']}:${dateOnly(day)}',
        title: row['title'] as String,
        kind:
            row['kind'] as String? ??
            (row['subject_id'] == null ? 'extra' : 'school'),
        start: calendarTime(day, row['start'] as String),
        end: calendarTime(day, row['end'] as String),
        note: row['note'] as String? ?? '',
        place: row['place'] as String? ?? '',
        reminder: row.containsKey('reminder_minutes')
            ? row['reminder_minutes'] as int?
            : 30,
        source: row,
        color: row['color'] as String?,
        activities: calendarActivities(row['activities']),
      ),
    );
  }
  final members = {
    for (final m in calendarRows(snapshot, 'members')) m['id']: m['name'],
  };
  for (final row in calendarRows(snapshot, 'tasks')) {
    if (row['status'] == 'cancelled') continue;
    final start = row['planned_start'] == null
        ? null
        : familyClock(snapshot, DateTime.parse(row['planned_start'] as String));
    final end = row['planned_end'] == null
        ? null
        : familyClock(snapshot, DateTime.parse(row['planned_end'] as String));
    final due = familyClock(snapshot, DateTime.parse(row['due_at'] as String));
    final planned = start != null && end != null;
    if (planned &&
        dateOnly(due) == dateOnly(day) &&
        dateOnly(end.subtract(const Duration(microseconds: 1))) !=
            dateOnly(due)) {
      entries.add(
        CalendarEntry(
          key: 'task:deadline:${row['id']}:${dateOnly(day)}',
          title: row['title'] as String,
          kind: row['subject_id'] == null ? 'task' : 'homework',
          start: due,
          end: due,
          deadline: true,
          source: row,
          note: 'Срок выполнения запланированного задания',
          reminder: ['assigned', 'returned'].contains(row['status'])
              ? (row.containsKey('reminder_minutes')
                    ? row['reminder_minutes'] as int?
                    : 30)
              : null,
        ),
      );
    }
    if (planned
        ? !start.isBefore(tomorrow) || !end.isAfter(day)
        : dateOnly(due) != dateOnly(day)) {
      continue;
    }
    entries.add(
      CalendarEntry(
        key: 'task:${row['id']}:${dateOnly(day)}',
        title: row['title'] as String,
        kind: row['subject_id'] == null ? 'task' : 'homework',
        start: planned ? (start.isBefore(day) ? day : start) : due,
        end: planned ? (end.isAfter(tomorrow) ? tomorrow : end) : due,
        note: [
          if (members[row['author_id']] != null)
            'От ${members[row['author_id']]}',
          statusText(row['status'] as String),
          taskKindText(row),
          if ((row['description'] as String? ?? '').isNotEmpty)
            row['description'],
        ].join(' · '),
        reminder: ['assigned', 'returned'].contains(row['status'])
            ? (row.containsKey('reminder_minutes')
                  ? row['reminder_minutes'] as int?
                  : 30)
            : null,
        source: row,
        deadline: !planned,
      ),
    );
  }
  entries.sort((a, b) {
    final cmp = a.start.compareTo(b.start);
    return cmp != 0 ? cmp : a.key.compareTo(b.key);
  });
  return entries;
}

Set<String> calendarConflicts(List<CalendarEntry> entries) {
  final occupied = entries.where((e) => !e.deadline).toList();
  final keys = <String>{};
  for (var i = 0; i < occupied.length; i++) {
    for (var j = i + 1; j < occupied.length; j++) {
      if (occupied[i].start.isBefore(occupied[j].end) &&
          occupied[j].start.isBefore(occupied[i].end)) {
        keys.addAll([occupied[i].key, occupied[j].key]);
      }
    }
  }
  return keys;
}

List<CalendarEntry> morningEntries(List<CalendarEntry> entries) {
  // Legacy individual lessons may be grouped; explicit blocks retain their agenda.
  final result = <CalendarEntry>[];
  for (final e in entries) {
    final previous = result.isEmpty ? null : result.last;
    if (e.activities.isEmpty &&
        previous?.activities.isEmpty == true &&
        e.color == previous?.color &&
        e.kind == 'school' &&
        previous?.kind == 'school' &&
        !e.start.isBefore(previous!.end) &&
        e.start.difference(previous.end).inMinutes <= 30) {
      result[result.length - 1] = CalendarEntry(
        key: '${previous.key}+${e.key}',
        title: 'Сегодня школа',
        kind: 'school',
        start: previous.start,
        end: e.end,
        note:
            '${previous.title == 'Сегодня школа' ? previous.note : previous.title}, ${e.title}',
        place: previous.place,
        color: previous.color,
      );
    } else {
      result.add(e);
    }
  }
  return result;
}

class CalendarReminder {
  int id;
  final String key, body, payload;
  final tz.TZDateTime at;
  CalendarReminder(CalendarEntry e, this.at)
    : key = e.key,
      id =
          1000000000 +
          (int.parse(
                sha256.convert(utf8.encode(e.key)).toString().substring(0, 8),
                radix: 16,
              ) %
              1000000000),
      body =
          '${e.deadline ? 'Срок задания' : 'Скоро'}: ${e.title} · ${e.timeText}',
      payload = 'calendar:${dateOnly(e.start)}';
  String get fingerprint => '$key|${at.toIso8601String()}|$body|$payload';
  CalendarReminder.assistant(AssistantHint hint, this.at)
    : key = hint.key,
      body = '${hint.message}\n${hint.title} · ${clockText(hint.start)}',
      payload = 'calendar:${dateOnly(hint.start)}',
      id =
          1000000000 +
          (int.parse(
                sha256
                    .convert(utf8.encode(hint.key))
                    .toString()
                    .substring(0, 8),
                radix: 16,
              ) %
              1000000000);
}

List<CalendarReminder> calendarReminders(
  Map<String, dynamic> snapshot,
  DateTime now,
) {
  final current = familyClock(snapshot, now);
  final family = snapshot['family'] as Map;
  int minute(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  final quietStart = minute(family['quiet_start'] as String? ?? '21:00');
  final quietEnd = minute(family['quiet_end'] as String? ?? '08:00');
  final result = <CalendarReminder>[];
  for (var offset = 0; offset <= 21; offset++) {
    final day = tz.TZDateTime(
      current.location,
      current.year,
      current.month,
      current.day + offset,
    );
    for (final e in calendarDay(snapshot, day)) {
      if (e.reminder == null) continue;
      if (!e.deadline &&
          e.source?['planned_start'] != null &&
          dateOnly(
                familyClock(
                  snapshot,
                  DateTime.parse(e.source!['planned_start'] as String),
                ),
              ) !=
              dateOnly(day)) {
        continue;
      }
      final at = e.start.subtract(Duration(minutes: e.reminder!));
      final t = at.hour * 60 + at.minute;
      final quiet = quietStart == quietEnd
          ? false
          : quietStart < quietEnd
          ? t >= quietStart && t < quietEnd
          : t >= quietStart || t < quietEnd;
      if (at.isAfter(current) &&
          at.isBefore(current.add(const Duration(days: 14))) &&
          !quiet) {
        result.add(CalendarReminder(e, at));
      }
    }
    if (snapshot['user']?['role'] == 'child') {
      for (final hint in assistantHints(snapshot, day)) {
        final at = hint.start.subtract(Duration(minutes: hint.minutesBefore));
        final t = at.hour * 60 + at.minute;
        final quiet = quietStart == quietEnd
            ? false
            : quietStart < quietEnd
            ? t >= quietStart && t < quietEnd
            : t >= quietStart || t < quietEnd;
        if (at.isAfter(current) &&
            at.isBefore(current.add(const Duration(days: 14))) &&
            !quiet) {
          result.add(CalendarReminder.assistant(hint, at));
        }
      }
    }
  }
  // Resolve rare truncated-hash collisions deterministically before registration.
  result.sort((a, b) => a.key.compareTo(b.key));
  final used = <int>{};
  for (final reminder in result) {
    while (!used.add(reminder.id)) {
      reminder.id = 1000000000 + (reminder.id - 1000000000 + 1) % 1000000000;
    }
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  return result.take(200).toList();
}
