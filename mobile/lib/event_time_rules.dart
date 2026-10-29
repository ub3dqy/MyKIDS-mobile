import 'package:flutter/material.dart';

int eventMinutes(TimeOfDay time) => time.hour * 60 + time.minute;
String eventClock(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

TimeOfDay? nextLessonStart(TimeOfDay previousEnd) {
  final minutes = eventMinutes(previousEnd) + 10;
  // A same-day lesson still needs at least a minute before 23:59.
  return minutes >= 1439
      ? null
      : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

class EventLessonTime {
  final String title;
  final TimeOfDay start, end;
  const EventLessonTime(this.title, this.start, this.end);
  EventLessonTime copyWith({TimeOfDay? start, TimeOfDay? end}) =>
      EventLessonTime(title, start ?? this.start, end ?? this.end);
  String get range => '${eventClock(start)} — ${eventClock(end)}';
}

enum LessonProblemKind { reversed, overlap, outside }

class LessonTimeProblem {
  final LessonProblemKind kind;
  final String message;
  const LessonTimeProblem(this.kind, this.message);
}

LessonTimeProblem? lessonTimeProblem(
  List<EventLessonTime> lessons,
  TimeOfDay start,
  TimeOfDay end, {
  bool allowOverlap = false,
}) {
  for (final lesson in lessons) {
    if (eventMinutes(lesson.end) <= eventMinutes(lesson.start)) {
      return LessonTimeProblem(
        LessonProblemKind.reversed,
        '${lesson.title}: окончание должно быть позже начала (${lesson.range}).',
      );
    }
  }
  final ordered = [...lessons]
    ..sort((a, b) => eventMinutes(a.start).compareTo(eventMinutes(b.start)));
  for (var i = 1; i < ordered.length; i++) {
    final previous = ordered
        .take(i)
        .reduce((a, b) => eventMinutes(a.end) > eventMinutes(b.end) ? a : b);
    if (!allowOverlap &&
        eventMinutes(ordered[i].start) < eventMinutes(previous.end)) {
      return LessonTimeProblem(
        LessonProblemKind.overlap,
        'Занятия пересекаются: ${previous.title} (${previous.range}) и ${ordered[i].title} (${ordered[i].range}).',
      );
    }
  }
  for (final lesson in lessons) {
    if (eventMinutes(lesson.start) < eventMinutes(start) ||
        eventMinutes(lesson.end) > eventMinutes(end)) {
      return LessonTimeProblem(
        LessonProblemKind.outside,
        '${lesson.title} (${lesson.range}) выходит за время события ${eventClock(start)} — ${eventClock(end)}.',
      );
    }
  }
  return null;
}

(TimeOfDay, TimeOfDay) expandedEventTimes(
  List<EventLessonTime> lessons,
  TimeOfDay start,
  TimeOfDay end,
) {
  for (final lesson in lessons) {
    if (eventMinutes(lesson.start) < eventMinutes(start)) {
      start = lesson.start;
    }
    if (eventMinutes(lesson.end) > eventMinutes(end)) {
      end = lesson.end;
    }
  }
  return (start, end);
}
