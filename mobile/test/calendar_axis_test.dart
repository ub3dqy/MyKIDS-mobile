import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_axis.dart';

void main() {
  test('empty full day stays compact and includes midnight boundaries', () {
    final axis = CalendarTimeAxis();
    expect(axis.height, 24 * 28);
    expect(axis.offsetAt(0), 0);
    expect(axis.offsetAt(1440), axis.height);
    for (var hour = 0; hour < 24; hour++) {
      expect(axis.heightBetween(hour * 60, (hour + 1) * 60), 28);
    }
  });
  test(
    'short event expands its own interval without stretching empty minutes',
    () {
      final axis = CalendarTimeAxis(
        needs: [const CalendarHeightNeed(610, 620, 120)],
      );
      expect(axis.heightBetween(610, 620), closeTo(120, .001));
      expect(axis.heightBetween(600, 610), closeTo(28 / 6, .001));
      expect(axis.heightBetween(620, 660), closeTo(28 * 2 / 3, .001));
      expect(axis.heightBetween(660, 720), closeTo(28, .001));
      expect(axis.height, lessThan(24 * 28 + 120));
    },
  );
  test('touching events and shared weekly constraints preserve time order', () {
    final axis = CalendarTimeAxis(
      needs: [
        const CalendarHeightNeed(540, 840, 350),
        const CalendarHeightNeed(600, 610, 90),
        const CalendarHeightNeed(610, 630, 120),
      ],
    );
    expect(axis.heightBetween(540, 840), greaterThanOrEqualTo(349.999));
    expect(axis.heightBetween(600, 610), greaterThanOrEqualTo(89.999));
    expect(axis.heightBetween(610, 630), greaterThanOrEqualTo(119.999));
    expect(axis.offsetAt(610), greaterThan(axis.offsetAt(600)));
    expect(axis.heightBetween(840, 900), closeTo(28, .001));
    expect(axis.offsetAt(1440), axis.height);
  });
}
