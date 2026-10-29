import 'package:flutter/material.dart';

import 'calendar.dart';

const eventColors = {
  'blue': ('Синий', Color(0xffdbe8ff), Color(0xff1559b3)),
  'green': ('Зелёный', Color(0xffdcf1e3), Color(0xff217348)),
  'purple': ('Фиолетовый', Color(0xffebe0fa), Color(0xff7240a4)),
  'yellow': ('Жёлтый', Color(0xffffedba), Color(0xff946500)),
  'pink': ('Розовый', Color(0xffffdfe6), Color(0xffa63860)),
  'gray': ('Серый', Color(0xffe7eaf0), Color(0xff526073)),
};

String defaultEventColor(String kind) => switch (kind) {
  'school' => 'blue',
  'extra' => 'purple',
  'homework' || 'task' => 'yellow',
  'free' => 'green',
  _ => 'pink',
};

Color eventBackground(CalendarEntry entry) =>
    eventColors[entry.color ?? defaultEventColor(entry.kind)]?.$2 ??
    eventColors['blue']!.$2;

Color eventAccent(CalendarEntry entry) =>
    eventColors[entry.color ?? defaultEventColor(entry.kind)]?.$3 ??
    eventColors['blue']!.$3;

class EventActivities extends StatelessWidget {
  final List<CalendarActivity> activities;
  const EventActivities({super.key, required this.activities});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in activities)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.start.substring(0, 5)} — ${item.end.substring(0, 5)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(item.title),
            ],
          ),
        ),
    ],
  );
}
