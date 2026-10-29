/// Only server-confirmed changes may celebrate earnings. A first snapshot is a
/// baseline, including after switching accounts; historical entries stay quiet.
class ChildReward {
  final int coins;
  const ChildReward(this.coins);
}

class ChildRewardTracker {
  String? identity;
  Set<String> seen = {};

  ChildReward? observe(Map<String, dynamic>? snapshot) {
    final user = snapshot?['user'];
    if (user == null || user['role'] != 'child') {
      identity = null;
      seen = {};
      return null;
    }
    final entries = (snapshot?['ledger'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final ids = entries.map((e) => e['id'] as String).toSet();
    if (identity != user['id']) {
      identity = user['id'] as String?;
      seen = ids;
      return null;
    }
    final awards = entries
        .where(
          (e) =>
              !seen.contains(e['id']) &&
              e['child_id'] == identity &&
              ['task', 'grade'].contains(e['source_type']) &&
              ((e['actual'] as num) > 0 ||
                  (e['source_type'] == 'task' && (e['actual'] as num) == 0)),
        )
        .toList();
    seen = ids;
    return awards.isEmpty
        ? null
        : ChildReward(
            awards.fold<int>(0, (sum, e) => sum + (e['actual'] as num).toInt()),
          );
  }
}
