import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar.dart';
import 'event_style.dart';
import 'schedule.dart';

class CalendarMonth extends StatelessWidget {
  final tz.TZDateTime selected;
  final List<CalendarEntry> Function(DateTime) entries;
  final void Function(DateTime) select;
  const CalendarMonth({
    super.key,
    required this.selected,
    required this.entries,
    required this.select,
  });
  @override
  Widget build(BuildContext context) {
    final first = tz.TZDateTime(
      selected.location,
      selected.year,
      selected.month,
      1,
    );
    final count = tz.TZDateTime(
      selected.location,
      selected.year,
      selected.month + 1,
      0,
    ).day;
    final today = tz.TZDateTime.now(selected.location);
    return LayoutBuilder(
      builder: (context, size) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final cellHeight = 72.0 * scale;
        return Column(
          children: [
            Row(
              children: [
                for (final label in calendarWeekdays)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
            for (
              var week = 0;
              week < ((first.weekday - 1 + count) / 7).ceil();
              week++
            )
              Row(
                children: [
                  for (var column = 0; column < 7; column++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final number = week * 7 + column - first.weekday + 2;
                          if (number < 1 || number > count) {
                            return SizedBox(height: cellHeight);
                          }
                          final date = tz.TZDateTime(
                            selected.location,
                            selected.year,
                            selected.month,
                            number,
                          );
                          final rows = entries(date);
                          final chosen = dateOnly(date) == dateOnly(selected);
                          final current = dateOnly(date) == dateOnly(today);
                          return Semantics(
                            selected: chosen,
                            button: true,
                            label:
                                '${calendarDateLabel(date)}, событий ${rows.length}',
                            child: InkWell(
                              key: ValueKey('calendar-day-${dateOnly(date)}'),
                              onTap: () => select(date),
                              child: Container(
                                height: cellHeight,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: chosen
                                      ? const Color(0xffe8f0ff)
                                      : Colors.white,
                                  border: Border.all(
                                    color: const Color(0xffe1e5eb),
                                    width: .5,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '$number',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: chosen || current
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: current
                                            ? const Color(0xff1559b3)
                                            : const Color(0xff26344b),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (size.maxWidth >= 700 * scale)
                                      for (final entry in rows.take(2))
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(
                                            bottom: 3,
                                          ),
                                          color: eventBackground(entry),
                                          child: Text(
                                            entry.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                        )
                                    else
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 3,
                                        runSpacing: 3,
                                        children: [
                                          for (final entry in rows.take(3))
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: eventAccent(entry),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                    if (rows.length >
                                        (size.maxWidth >= 700 * scale ? 2 : 3))
                                      Text(
                                        '+${rows.length - (size.maxWidth >= 700 * scale ? 2 : 3)}',
                                        style: const TextStyle(fontSize: 9),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
