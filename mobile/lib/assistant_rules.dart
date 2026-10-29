import 'package:timezone/timezone.dart' as tz;

import 'calendar.dart';

const defaultAssistantRules = [
  {
    'id': 'physical_education',
    'title': 'Физическая культура',
    'keywords': ['физическая культура', 'физкультура'],
    'message': 'Возьми с собой форму для физкультуры и спортивную обувь.',
    'minutes_before': 45,
    'enabled': true,
  },
  {
    'id': 'music_school',
    'title': 'Музыкальная школа',
    'keywords': ['музыкальная школа'],
    'message': 'Возьми с собой папку для музыкальной школы.',
    'minutes_before': 45,
    'enabled': true,
  },
  {
    'id': 'rugby',
    'title': 'Регби',
    'keywords': ['регби'],
    'message': 'Собери сумку для регби и налей воды.',
    'minutes_before': 45,
    'enabled': true,
  },
];

List<Map<String, dynamic>> assistantRules(Map<String, dynamic> snapshot) =>
    (snapshot['assistant_rules'] as List? ?? defaultAssistantRules)
        .map((rule) => Map<String, dynamic>.from(rule as Map))
        .toList();

String _normal(String text) => text
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class AssistantHint {
  final String key, title, message;
  final tz.TZDateTime start;
  final int minutesBefore;
  const AssistantHint(
    this.key,
    this.title,
    this.message,
    this.start,
    this.minutesBefore,
  );
}

List<AssistantHint> assistantHints(
  Map<String, dynamic> snapshot,
  DateTime day,
) {
  final result = <AssistantHint>[];
  for (final rule in assistantRules(snapshot)) {
    if (rule['enabled'] != true) continue;
    final words = (rule['keywords'] as List)
        .cast<String>()
        .map(_normal)
        .where((word) => word.isNotEmpty)
        .toList();
    bool matches(String title) =>
        words.any((word) => _normal(title).contains(word));
    void add(
      CalendarEntry entry,
      String target,
      String title,
      tz.TZDateTime start,
    ) {
      result.add(
        AssistantHint(
          'assistant:${rule['id']}:${entry.key}:$target',
          title,
          rule['message'] as String,
          start,
          rule['minutes_before'] as int,
        ),
      );
    }

    for (final entry in calendarDay(snapshot, day)) {
      if (entry.deadline) continue;
      if (matches(entry.title)) {
        add(entry, 'event', entry.title, entry.start);
      } else {
        for (var i = 0; i < entry.activities.length; i++) {
          final lesson = entry.activities[i];
          if (matches(lesson.title)) {
            add(
              entry,
              lesson.id ?? '$i',
              lesson.title,
              calendarTime(entry.start, lesson.start),
            );
          }
        }
      }
    }
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}
