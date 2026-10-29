import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar.dart';
import 'calendar_axis.dart';
import 'event_style.dart';
import 'schedule.dart';

class _Position {
  final CalendarEntry entry;
  final int column;
  int columns = 1;
  _Position(this.entry, this.column);
}

int _endMinute(CalendarEntry entry) =>
    dateOnly(entry.end) != dateOnly(entry.start)
    ? 24 * 60
    : entry.end.hour * 60 + entry.end.minute;

// Each connected group of overlapping events shares columns. Touching endpoints
// do not overlap; an activity inside an event is never treated as another event.
List<_Position> _positions(List<CalendarEntry> entries) {
  final result = <_Position>[];
  final ordered = entries.where((entry) => !entry.deadline).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final ends = <DateTime>[];
  final group = <_Position>[];
  void finish() {
    for (final position in group) {
      position.columns = ends.length;
    }
    group.clear();
    ends.clear();
  }

  for (final entry in ordered) {
    if (group.isNotEmpty && ends.every((end) => !end.isAfter(entry.start))) {
      finish();
    }
    var column = ends.indexWhere((end) => !end.isAfter(entry.start));
    if (column < 0) {
      column = ends.length;
      ends.add(entry.end);
    } else {
      ends[column] = entry.end;
    }
    final position = _Position(entry, column);
    group.add(position);
    result.add(position);
  }
  finish();
  return result;
}

class CalendarTimeline extends StatelessWidget {
  final List<tz.TZDateTime> days;
  final List<CalendarEntry> Function(DateTime) entries;
  final void Function(CalendarEntry) open;
  final void Function(tz.TZDateTime, TimeOfDay)? create;
  const CalendarTimeline({
    super.key,
    required this.days,
    required this.entries,
    required this.open,
    this.create,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final body = Theme.of(context).textTheme.bodyMedium!;
      final labelStyle = body.copyWith(
        fontSize: 10,
        color: const Color(0xff566275),
      );
      final labelHeight = _textHeight(
        context,
        '24:00',
        labelStyle,
        double.infinity,
      );
      final axisWidth = math.max(
        44.0,
        _textWidth(context, '24:00', labelStyle) + 8,
      );
      final emptyHourHeight = math.max(28.0, labelHeight + 8);
      var dayWidth = days.length == 1
          ? math.max(180.0, constraints.maxWidth - axisWidth)
          : math.max(
              160.0 * scale,
              (constraints.maxWidth - axisWidth) / days.length,
            );
      final dayRows = [for (final day in days) entries(day)];
      final positions = [for (final rows in dayRows) _positions(rows)];
      for (final rows in positions) {
        for (final position in rows) {
          dayWidth = math.max(dayWidth, position.columns * 80 * scale);
        }
      }
      final axis = CalendarTimeAxis(
        emptyHourHeight: emptyHourHeight,
        needs: [
          for (final rows in positions)
            for (final position in rows)
              CalendarHeightNeed(
                position.entry.start.hour * 60 + position.entry.start.minute,
                _endMinute(position.entry),
                _eventHeight(
                      context,
                      position.entry,
                      dayWidth / position.columns - 6,
                    ) +
                    2,
              ),
        ],
      );
      final height = axis.height + labelHeight + 8;
      final now = familyClock(null);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: axisWidth + dayWidth * days.length,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: axisWidth),
                  for (final day in days)
                    SizedBox(
                      width: dayWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 6,
                        ),
                        child: Text(
                          '${calendarWeekdays[day.weekday - 1]}, ${day.day}.${day.month}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color:
                                dateOnly(day) ==
                                    dateOnly(
                                      tz.TZDateTime.from(now, day.location),
                                    )
                                ? const Color(0xff1559b3)
                                : const Color(0xff26344b),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (dayRows.any((rows) => rows.any((entry) => entry.deadline)))
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: axisWidth,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Text('Срок', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    for (final rows in dayRows)
                      SizedBox(
                        width: dayWidth,
                        child: Column(
                          children: [
                            for (final entry in rows.where(
                              (entry) => entry.deadline,
                            ))
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Material(
                                  color: eventBackground(entry),
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    onTap: () => open(entry),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        '${entry.timeText}\n${entry.title}',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: axisWidth,
                    height: height,
                    child: Stack(
                      children: [
                        for (var hour = 0; hour <= 24; hour++)
                          Positioned(
                            top: axis.offsetAt(hour * 60),
                            left: 2,
                            right: 4,
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00',
                              key: ValueKey('calendar-hour-$hour'),
                              textAlign: TextAlign.right,
                              style: labelStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var index = 0; index < days.length; index++)
                    SizedBox(
                      width: dayWidth,
                      height: height,
                      child: Stack(
                        children: [
                          Positioned(
                            top: axis.height,
                            left: 0,
                            right: 0,
                            child: Container(
                              key: ValueKey(
                                'calendar-day-end-${dateOnly(days[index])}',
                              ),
                              height: 1,
                              color: const Color(0xffdce1e8),
                            ),
                          ),
                          for (var hour = 0; hour < 24; hour++)
                            Positioned(
                              top: axis.offsetAt(hour * 60),
                              left: 0,
                              right: 0,
                              height: axis.heightBetween(
                                hour * 60,
                                (hour + 1) * 60,
                              ),
                              key: ValueKey(
                                'calendar-cell-${dateOnly(days[index])}-$hour',
                              ),
                              child: Semantics(
                                button: create != null,
                                label: create == null
                                    ? null
                                    : 'Добавить событие: ${calendarDateLabel(days[index])}, $hour:00',
                                child: InkWell(
                                  onTap: create == null
                                      ? null
                                      : () => create!(
                                          days[index],
                                          TimeOfDay(hour: hour, minute: 0),
                                        ),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: Color(0xffdce1e8),
                                        ),
                                        left: BorderSide(
                                          color: Color(0xffdce1e8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          for (final position in positions[index])
                            Positioned(
                              top: axis.offsetAt(
                                position.entry.start.hour * 60 +
                                    position.entry.start.minute,
                              ),
                              left:
                                  position.column *
                                      dayWidth /
                                      position.columns +
                                  3,
                              width: dayWidth / position.columns - 6,
                              height:
                                  axis.heightBetween(
                                    position.entry.start.hour * 60 +
                                        position.entry.start.minute,
                                    _endMinute(position.entry),
                                  ) -
                                  2,
                              child: _GridEvent(
                                entry: position.entry,
                                open: () => open(position.entry),
                              ),
                            ),
                          if (dateOnly(days[index]) ==
                              dateOnly(
                                tz.TZDateTime.from(now, days[index].location),
                              ))
                            Builder(
                              builder: (context) {
                                final local = tz.TZDateTime.from(
                                  now,
                                  days[index].location,
                                );
                                final minute = local.hour * 60 + local.minute;
                                return Positioned(
                                  top: axis.offsetAt(minute),
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(
                                    child: Container(
                                      height: 2,
                                      color: const Color(0xffc53b39),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _GridEvent extends StatelessWidget {
  final CalendarEntry entry;
  final VoidCallback open;
  const _GridEvent({required this.entry, required this.open});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${entry.title}, ${entry.timeText}, занятий ${entry.activities.length}',
    child: Material(
      color: eventBackground(entry),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: eventAccent(entry), width: 4),
            ),
          ),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(entry.title, style: _titleStyle(context)),
                  Text(entry.timeText, style: _timeStyle(context)),
                  if (entry.note.isNotEmpty) Text(entry.note),
                  EventActivities(activities: entry.activities),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

TextStyle _titleStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 14, fontWeight: FontWeight.w700);
TextStyle _timeStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 12);

double _textHeight(
  BuildContext context,
  String value,
  TextStyle style,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout(maxWidth: math.max(1, width));
  final height = painter.height;
  painter.dispose();
  return height;
}

double _textWidth(BuildContext context, String value, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

double _eventHeight(BuildContext context, CalendarEntry entry, double width) {
  final contentWidth = math.max(1.0, width - 20);
  final body = Theme.of(context).textTheme.bodyMedium!;
  var height =
      16.0 +
      _textHeight(context, entry.title, _titleStyle(context), contentWidth) +
      _textHeight(context, entry.timeText, _timeStyle(context), contentWidth);
  if (entry.note.isNotEmpty) {
    height += _textHeight(context, entry.note, body, contentWidth);
  }
  for (final item in entry.activities) {
    height +=
        12 +
        _textHeight(
          context,
          '${item.start.substring(0, 5)} — ${item.end.substring(0, 5)}',
          body.copyWith(fontWeight: FontWeight.w700),
          contentWidth,
        ) +
        _textHeight(context, item.title, body, contentWidth);
  }
  return math.max(48, height.ceilToDouble());
}
