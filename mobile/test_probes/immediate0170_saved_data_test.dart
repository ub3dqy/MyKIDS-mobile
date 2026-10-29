import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/task_rules.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  tzdata.initializeTimeZones();
  final path = Platform.environment['IMMEDIATE0170_PROOF'];
  if (path == null) {
    throw StateError('Actual offline-upgrade emulator evidence required');
  }
  Map read(String name) =>
      jsonDecode(File('$path/$name').readAsStringSync()) as Map;
  final upgrade = read('upgrade-complete.json');
  final barrier = read('barrier.json');
  final phases = [
    read('automatic-send.json'),
    read('automatic-credit.json'),
    read('repeat-network-and-delivery.json'),
  ];
  final day = DateTime.parse(upgrade['completed_utc'] as String);
  int pending(Map<String, dynamic> snapshot) => calendarRows(snapshot, 'tasks')
      .where(
        (task) =>
            task['status'] == 'submitted' &&
            canReviewTask(snapshot['user'], task),
      )
      .length;
  int active(Map<String, dynamic> snapshot) => calendarRows(snapshot, 'tasks')
      .where(
        (task) =>
            ['assigned', 'returned', 'submitted'].contains(task['status']),
      )
      .length;
  for (final actor in ['kid', 'papa', 'mama']) {
    test('offline upgrade preserves the real pending queue for $actor', () {
      final role = upgrade['roles'][actor] as Map;
      final before = barrier['before'][actor] as Map;
      expect(role['old']['code'], '69');
      expect(role['new']['code'], '70');
      expect(role['old']['uid'], role['new']['uid']);
      expect(role['old']['first_install'], role['new']['first_install']);
      expect(role['outbox_rows_preserved'], actor == 'kid' ? 2 : 1);
      expect(role['photos_preserved'], actor == 'kid' ? 4 : 0);
      expect(before['outbox'], hasLength(actor == 'kid' ? 2 : 1));
      expect(before['snapshot']['balance']['total'], 500);
      expect(before['snapshot']['balance']['reserved'], 150);
      expect(role['new_activity_started'], false);
      expect(barrier['queue_created_via_normal_old_app_ui'], true);
      expect(barrier['private_outbox_injected'], false);
    });
  }
  for (var index = 0; index < phases.length; index++) {
    final phase = phases[index];
    for (final actor in ['kid', 'papa', 'mama']) {
      test(
        'offline recovery phase $index: actual saved data and counters for $actor',
        () {
          final actual = Map<String, dynamic>.from(
            phase['snapshots'][actor] as Map,
          );
          final expected = Map<String, dynamic>.from(
            phase['expected'][actor] as Map,
          );
          expect(actual['balance']['total'], index == 0 ? 500 : 575);
          expect(actual['balance']['reserved'], 150);
          expect(actual['balance']['available'], index == 0 ? 350 : 425);
          expect(pending(actual), actor == 'kid' ? 0 : (index == 0 ? 3 : 1));
          expect(active(actual), index == 0 ? 5 : 3);
          for (final key in [
            'tasks',
            'ledger',
            'redemptions',
            'rooms',
            'schedules',
          ]) {
            expect(actual[key], expected[key]);
          }
          expect(
            calendarDay(
              actual,
              day,
            ).map((entry) => [entry.key, entry.title, entry.timeText]).toList(),
            calendarDay(
              expected,
              day,
            ).map((entry) => [entry.key, entry.title, entry.timeText]).toList(),
          );
          final photoTasks = calendarRows(actual, 'tasks')
              .where((task) => ['Фото А', 'Фото Б'].contains(task['title']))
              .toList();
          expect(photoTasks, hasLength(2));
          expect(photoTasks.map((task) => task['status']).toSet(), {
            index == 0 ? 'submitted' : 'completed',
          });
        },
      );
    }
  }
}
