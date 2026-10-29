import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/task_rules.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  tzdata.initializeTimeZones();
  final path = Platform.environment['UPGRADE0168_PROOF'];
  if (path == null) {
    throw StateError('Actual emulator upgrade evidence required');
  }
  final root = Directory(path);
  final upgrade = jsonDecode(
    File('${root.path}/upgrade-complete.json').readAsStringSync(),
  ) as Map;
  final background = jsonDecode(
    File('${root.path}/background-complete.json').readAsStringSync(),
  ) as Map;
  final day = DateTime.parse(upgrade['completed_utc'] as String);
  List<List<Object?>> calendar(Map<String, dynamic> data) => calendarDay(
    data,
    day,
  ).map((e) => <Object?>[e.key, e.title, e.timeText]).toList();
  int pending(Map<String, dynamic> data) => calendarRows(data, 'tasks')
      .where(
        (task) =>
            task['status'] == 'submitted' && canReviewTask(data['user'], task),
      )
      .length;
  int active(Map<String, dynamic> data) => calendarRows(data, 'tasks')
      .where(
        (task) =>
            ['assigned', 'returned', 'submitted'].contains(task['status']),
      )
      .length;
  int unread(Map<String, dynamic> data) => calendarRows(
    data,
    'rooms',
  ).fold(0, (sum, room) => sum + (room['unread_count'] as int? ?? 0));
  int requests(Map<String, dynamic> data) => calendarRows(
    data,
    'redemptions',
  ).where((request) => request['status'] == 'pending').length;
  for (final actor in ['kid', 'papa', 'mama']) {
    test(
      'published 68 to 69: saved calendar, coins and counters for $actor',
      () {
        final role = upgrade['roles'][actor] as Map;
        final before = Map<String, dynamic>.from(
          role['before_snapshot'] as Map,
        );
        final after = Map<String, dynamic>.from(role['after_snapshot'] as Map);
        expect(after, before);
        expect(after['balance']['total'], 500);
        expect(after['balance']['reserved'], 150);
        expect(after['balance']['available'], 350);
        expect(pending(after), actor == 'kid' ? 0 : 1);
        expect(active(after), 1);
        expect(unread(after), 1);
        expect(requests(after), 1);
        expect(calendar(after), calendar(before));
        expect(role['photos'], hasLength(2));
        expect(role['new_main_activity_started'], false);
      },
    );
  }
  final phases = background['phases'] as List;
  if (phases.length != 3) throw StateError('Three background rounds required');
  for (var index = 0; index < 3; index++) {
    final phase = phases[index] as Map;
    for (final actor in ['kid', 'papa', 'mama']) {
      test(
        'background round ${index + 1}: persisted data and counters for $actor',
        () {
          final actual = Map<String, dynamic>.from(
            phase['receipts'][actor]['actual_snapshot'] as Map,
          );
          final expected = Map<String, dynamic>.from(
            phase['expected'][actor] as Map,
          );
          expect(calendar(actual), calendar(expected));
          for (final name in [
            'tasks',
            'grades',
            'rewards',
            'redemptions',
            'rooms',
            'ledger',
          ]) {
            expect(actual[name], expected[name]);
          }
          expect(actual['balance']['total'], index == 2 ? 630 : 570);
          expect(actual['balance']['reserved'], 0);
          expect(actual['balance']['available'], index == 2 ? 630 : 570);
          expect(pending(actual), actor != 'kid' && index == 1 ? 1 : 0);
          expect(active(actual), index == 1 ? 1 : 0);
          expect(unread(actual), index + 2);
          expect(requests(actual), 0);
          expect(phase['receipts'][actor]['completed_job']['state'], 2);
          expect(phase['no_manual_application_launch'], true);
        },
      );
    }
  }
}
