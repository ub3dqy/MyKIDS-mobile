import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/task_rules.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  tzdata.initializeTimeZones();
  final path = Platform.environment['UPGRADE7071_PROOF'];
  if (path == null) throw StateError('Actual three-emulator evidence required');
  final evidence = jsonDecode(
    File('$path/preservation-final.json').readAsStringSync(),
  ) as Map;
  final upgrade =
      jsonDecode(File('$path/upgrade-complete.json').readAsStringSync()) as Map;
  for (final phase in ['before', 'offline_after', 'snapshots']) {
    for (final actor in ['kid', 'papa', 'mama']) {
      test(
        '70 to 71: $phase saved money, calendar and counters for $actor',
        () {
          final data = Map<String, dynamic>.from(evidence[phase][actor] as Map);
          final before = Map<String, dynamic>.from(
            evidence['before'][actor] as Map,
          );
          final role = upgrade['roles'][actor] as Map;
          expect(role['old']['code'], '70');
          expect(role['new']['code'], '71');
          expect(role['old']['uid'], role['new']['uid']);
          expect(role['old']['first_install'], role['new']['first_install']);
          expect(role['all_database_rows_identical'], true);
          expect(role['encrypted_credentials_preserved'], true);
          expect(role['cached_photos_preserved'], 2);
          expect(data['user'], before['user']);
          expect(data['balance']['total'], 500);
          expect(data['balance']['reserved'], 150);
          expect(data['balance']['available'], 350);
          final tasks = calendarRows(data, 'tasks');
          expect(tasks, hasLength(2));
          expect(tasks.where((t) => t['status'] == 'submitted'), hasLength(1));
          expect(
            tasks.where(
              (t) =>
                  t['status'] == 'submitted' && canReviewTask(data['user'], t),
            ),
            hasLength(actor == 'kid' ? 0 : 1),
          );
          expect(
            calendarRows(
              data,
              'redemptions',
            ).where((r) => r['status'] == 'pending'),
            hasLength(1),
          );
          expect(
            calendarRows(
              data,
              'rooms',
            ).fold<int>(0, (n, r) => n + (r['unread_count'] as int)),
            1,
          );
          for (final key in [
            'tasks',
            'submissions',
            'ledger',
            'rewards',
            'redemptions',
            'rooms',
            'schedules',
            'members',
            'grades',
            'grade_rules',
          ]) {
            expect(data[key], before[key]);
          }
          for (final day in [
            DateTime(2026, 10, 16),
            DateTime(2026, 10, 19),
            DateTime(2026, 10, 20),
            DateTime(2026, 10, 22),
          ]) {
            expect(
              calendarDay(
                data,
                day,
              ).map((e) => [e.key, e.title, e.timeText]).toList(),
              calendarDay(
                before,
                day,
              ).map((e) => [e.key, e.title, e.timeText]).toList(),
            );
          }
        },
      );
    }
  }
}
