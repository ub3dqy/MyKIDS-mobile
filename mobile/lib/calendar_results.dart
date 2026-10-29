import 'calendar.dart';
import 'schedule.dart';

import 'package:timezone/timezone.dart' as tz;

class CalendarResultItem {
  final CalendarEntry entry;
  final CalendarActivity? activity;
  const CalendarResultItem(this.entry, [this.activity]);

  bool get task => entry.key.startsWith('task:');
  String get title => activity?.title ?? entry.title;
  String get key => task
      ? 'task:${entry.source!['id']}'
      : '${entry.key}:${activity?.id ?? activity?.start ?? 'event'}';
  String get timeText => activity == null
      ? entry.timeText
      : '${activity!.start.substring(0, 5)} — ${activity!.end.substring(0, 5)}';
  Map<String, dynamic> get gradeSource => {
    'schedule_id': entry.source!['id'],
    if (activity != null) 'activity_id': activity!.id,
  };
  bool get canGrade =>
      !task &&
      (activity != null
          ? schoolSubjects(entry.source!) && activity!.id != null
          : entry.activities.isEmpty &&
                !schoolBlockTitle(entry.title) &&
                schoolSubjects(entry.source!));

  bool matchesGrade(Map<String, dynamic> grade) =>
      !task &&
      grade['schedule_id'] == entry.source!['id'] &&
      grade['activity_id'] == activity?.id;
}

List<CalendarResultItem> calendarResultItems(
  Map<String, dynamic> snapshot,
  DateTime day,
) {
  final tasks = <String>{};
  final date = tz.TZDateTime(
    familyClock(snapshot).location,
    day.year,
    day.month,
    day.day,
    12,
  );
  return [
    for (final entry in calendarDay(snapshot, date))
      if (entry.source != null) ...[
        if (entry.key.startsWith('task:')
            ? tasks.add(entry.source!['id'] as String)
            : CalendarResultItem(entry).canGrade)
          CalendarResultItem(entry),
        for (final activity in entry.activities)
          if (CalendarResultItem(entry, activity).canGrade)
            CalendarResultItem(entry, activity),
      ],
  ];
}

String gradeTitle(Map<String, dynamic> grade, Map<String, String> subjects) =>
    grade['event_title'] as String? ??
    subjects[grade['subject_id']] ??
    'Событие';

Map<String, dynamic> calendarSubmission(Map<String, dynamic> task) => {
  'task_version': task['version'],
  'marked_at': DateTime.now().toUtc().toIso8601String(),
};

Map<String, dynamic> calendarCompletion(
  Map<String, dynamic> task,
  DateTime day,
) => {
  'action': 'complete',
  'date': dateOnly(day),
  'task_version': task['version'],
};
