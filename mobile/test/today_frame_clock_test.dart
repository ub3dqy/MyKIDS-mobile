import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/schedule.dart';

void main() {
  test('daily progress uses the same instant as the visible day', () {
    final snapshot = <String, dynamic>{
      'family': {'timezone': 'Europe/Moscow'},
    };
    final task = <String, dynamic>{
      'due_at': '2026-10-21T15:00:00+03:00',
      'status': 'completed',
    };
    expect(
      taskIsForToday(
        snapshot,
        task,
        now: DateTime.parse('2026-10-21T23:59:59+03:00'),
      ),
      isTrue,
    );
    expect(
      taskIsForToday(
        snapshot,
        task,
        now: DateTime.parse('2026-10-22T00:00:00+03:00'),
      ),
      isFalse,
    );
    task['status'] = 'assigned';
    expect(
      taskIsForToday(
        snapshot,
        task,
        now: DateTime.parse('2026-10-22T00:00:00+03:00'),
      ),
      isTrue,
    );
    task['due_at'] = '2026-10-23T15:00:00+03:00';
    expect(
      taskIsForToday(
        snapshot,
        task,
        now: DateTime.parse('2026-10-22T00:00:00+03:00'),
      ),
      isFalse,
    );
  });
}
