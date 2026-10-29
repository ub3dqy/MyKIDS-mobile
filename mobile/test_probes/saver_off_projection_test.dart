import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/task_rules.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  tzdata.initializeTimeZones();
  final path = Platform.environment['SAVER_OFF_SNAPSHOTS'];
  if (path == null) {
    throw StateError(
      'Provide the saved snapshots from actual emulator delivery',
    );
  }
  final cases = jsonDecode(File(path).readAsStringSync()) as List;
  if (cases.length != 6) {
    throw StateError('All six real delivery scenarios are required');
  }
  for (final item in cases) {
    for (final actor in ['kid', 'papa', 'mama']) {
      test('${item['name']} actual saved calendar and counters: $actor', () {
        final actual = Map<String, dynamic>.from(
          item['snapshots'][actor] as Map,
        );
        final expected = Map<String, dynamic>.from(
          item['expected'][actor] as Map,
        );
        final day = DateTime.parse(item['date'] as String);
        final entries = calendarDay(actual, day);
        final authoritative = calendarDay(expected, day);
        expect(
          entries.map((e) => [e.key, e.title, e.timeText]).toList(),
          authoritative.map((e) => [e.key, e.title, e.timeText]).toList(),
        );
        final expectedCount = switch (item['name']) {
          'calendar_create_disable_asleep' || 'calendar_edit_cellular' => 1,
          'calendar_delete_cellular' => 0,
          'calendar_burst_cellular' => 2,
          'quiet_review_counter_added' || 'quiet_review_counter_cleared' => 3,
          _ => throw StateError('Unrecognized actual delivery scenario'),
        };
        expect(entries.length, expectedCount);
        expect(entries.map((e) => e.key).toSet().length, expectedCount);
        for (final key in ['tasks', 'redemptions', 'rooms']) {
          expect(actual[key], expected[key]);
        }
        expect(actual['balance']['total'], expected['balance']['total']);
        expect(actual['balance']['reserved'], expected['balance']['reserved']);
        final active = calendarRows(actual, 'tasks').where(
          (t) => ['assigned', 'returned', 'submitted'].contains(t['status']),
        );
        final review = active.where(
          (t) => t['status'] == 'submitted' && canReviewTask(actual['user'], t),
        );
        final pending = item['name'] == 'quiet_review_counter_added';
        expect(active.length, pending ? 1 : 0);
        expect(review.length, pending && actor != 'kid' ? 1 : 0);
      });
    }
  }
}
