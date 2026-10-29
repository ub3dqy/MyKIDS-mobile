import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/child_rewards.dart';

Map<String, dynamic> state(
  List<Map<String, dynamic>> entries, {
  String id = 'child',
  String role = 'child',
}) => {
  'user': {'id': id, 'role': role},
  'ledger': entries,
};
Map<String, dynamic> entry(
  String id,
  int amount, {
  String type = 'task',
  String child = 'child',
}) => {'id': id, 'child_id': child, 'source_type': type, 'actual': amount};
void main() {
  test(
    'historical rewards quiet; new confirmed credit once, actual amount',
    () {
      final tracker = ChildRewardTracker();
      final old = entry('old', 10);
      expect(tracker.observe(state([old])), isNull);
      final earned = {...entry('earned', 7), 'requested': 20};
      expect(tracker.observe(state([old, earned]))?.coins, 7);
      expect(tracker.observe(state([old, earned])), isNull);
    },
  );
  test(
    'submission, fines, redemptions and other children never earn rewards',
    () {
      final tracker = ChildRewardTracker()..observe(state([]));
      expect(
        tracker.observe({
          ...state([]),
          'tasks': [
            {'status': 'submitted', 'reward': 100},
          ],
        }),
        isNull,
      );
      expect(
        tracker.observe(
          state([
            entry('fine', -5),
            entry('withdraw', -10, type: 'redemption'),
            entry('refund', 10, type: 'refund'),
            entry('other', 5, child: 'other'),
          ]),
        ),
        isNull,
      );
    },
  );
  test(
    'zero coin completion still congratulates; batches sum actual credits',
    () {
      final tracker = ChildRewardTracker()..observe(state([]));
      expect(tracker.observe(state([entry('zero', 0)]))?.coins, 0);
      expect(
        tracker
            .observe(
              state([
                entry('zero', 0),
                entry('a', 5),
                entry('b', 3, type: 'grade'),
              ]),
            )
            ?.coins,
        8,
      );
    },
  );
  test('logout and account switch start a fresh baseline', () {
    final tracker = ChildRewardTracker()..observe(state([]));
    expect(tracker.observe(state([entry('a', 5)], id: 'other')), isNull);
    expect(tracker.observe(null), isNull);
    expect(tracker.observe(state([entry('old', 5)])), isNull);
    expect(tracker.observe(state([entry('new', 5)], role: 'parent')), isNull);
  });
}
