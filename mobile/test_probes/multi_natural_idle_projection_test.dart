import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/task_rules.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  tzdata.initializeTimeZones();
  final path = Platform.environment['MULTI_NATURAL_IDLE_SNAPSHOTS'];
  if (path == null) throw StateError('Actual three-cycle saved data required');
  final cases = jsonDecode(File(path).readAsStringSync()) as List;
  if (cases.length != 3) throw StateError('Three completed cycles required');
  for (var index = 0; index < 3; index++) {
    final item = cases[index];
    final cycle = index + 1;
    if (item['name'] != 'cycle_$cycle') throw StateError('Unexpected cycle');
    for (final actor in ['kid', 'papa', 'mama']) {
      test('natural cycle $cycle: saved calendar and counters for $actor', () {
        final actual = Map<String, dynamic>.from(
          item['snapshots'][actor] as Map,
        );
        final expected = Map<String, dynamic>.from(
          item['expected'][actor] as Map,
        );
        final before = Map<String, dynamic>.from(item['before'][actor] as Map);
        final day = DateTime.parse(item['date'] as String);
        final entries = calendarDay(actual, day);
        final count = cycle == 1 ? 3 : 4;
        expect(
          entries.map((e) => [e.key, e.title, e.timeText]).toList(),
          calendarDay(
            expected,
            day,
          ).map((e) => [e.key, e.title, e.timeText]).toList(),
        );
        expect(entries.length, count);
        expect(entries.map((e) => e.key).toSet().length, count);
        expect(
          entries.where((e) => e.title == 'Multi edited cycle $cycle').length,
          1,
        );
        expect(
          entries.any((e) => e.title == 'Multi deleted transient'),
          isFalse,
        );
        if (cycle > 1) {
          expect(entries.any((e) => e.title == 'Multi preflight'), isFalse);
        }
        if (cycle == 3) {
          expect(
            entries.any((e) => e.title == 'Multi second cycle 2'),
            isFalse,
          );
        }
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
        expect(active(before).length, cycle == 2 ? 0 : 1);
        expect(active(actual).length, cycle == 2 ? 1 : 0);
        int pending(Map<String, dynamic> snapshot) => active(snapshot)
            .where(
              (task) =>
                  task['status'] == 'submitted' &&
                  canReviewTask(snapshot['user'], task),
            )
            .length;
        expect(pending(before), actor != 'kid' && cycle != 2 ? 1 : 0);
        expect(pending(actual), actor != 'kid' && cycle == 2 ? 1 : 0);
      });
    }
  }
}
