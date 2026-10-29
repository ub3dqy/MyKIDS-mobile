import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/task_rules.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  tzdata.initializeTimeZones();
  final path = Platform.environment['NATURAL_IDLE_SNAPSHOTS'];
  if (path == null) {
    throw StateError('Provide actual saved snapshots after natural delivery');
  }
  final cases = jsonDecode(File(path).readAsStringSync()) as List;
  if (cases.length != 1 || cases.single['name'] != 'natural_exit') {
    throw StateError('A completed natural exit is required');
  }
  final item = cases.single;
  for (final actor in ['kid', 'papa', 'mama']) {
    test(
      'natural deep sleep: actual saved calendar and counters for $actor',
      () {
        final actual = Map<String, dynamic>.from(
          item['snapshots'][actor] as Map,
        );
        final expected = Map<String, dynamic>.from(
          item['expected'][actor] as Map,
        );
        final before = Map<String, dynamic>.from(item['before'][actor] as Map);
        final day = DateTime.parse(item['date'] as String);
        final entries = calendarDay(actual, day);
        expect(
          entries.map((e) => [e.key, e.title, e.timeText]).toList(),
          calendarDay(
            expected,
            day,
          ).map((e) => [e.key, e.title, e.timeText]).toList(),
        );
        expect(entries.length, 3);
        expect(entries.map((e) => e.key).toSet().length, 3);
        expect(
          entries.where((e) => e.title == 'Natural pending edited').length,
          1,
        );
        expect(
          entries.any((e) => e.title == 'Natural transient deleted'),
          isFalse,
        );
        for (final key in ['tasks', 'redemptions', 'rooms']) {
          expect(actual[key], expected[key]);
        }
        for (final key in ['total', 'reserved', 'available']) {
          expect(actual['balance'][key], expected['balance'][key]);
          expect(actual['balance'][key], before['balance'][key]);
        }
        List<Map<String, dynamic>> active(Map<String, dynamic> snapshot) =>
            calendarRows(snapshot, 'tasks')
                .where(
                  (task) => [
                    'assigned',
                    'returned',
                    'submitted',
                  ].contains(task['status']),
                )
                .toList();
        expect(active(before).length, 1);
        expect(active(actual), isEmpty);
        expect(
          active(before)
              .where(
                (task) =>
                    task['status'] == 'submitted' &&
                    canReviewTask(before['user'], task),
              )
              .length,
          actor == 'kid' ? 0 : 1,
        );
        expect(
          active(actual).where((task) => canReviewTask(actual['user'], task)),
          isEmpty,
        );
      },
    );
  }
}
