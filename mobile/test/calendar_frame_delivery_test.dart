import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/morning.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  for (final kind in ['school', 'extra', 'task']) {
    testWidgets('$kind: delayed drawing never skips an authored pose', (
      tester,
    ) async {
      final strip = kind == 'school' ? 'book' : kind;
      await tester.runAsync(
        () => precacheRasterArtwork(['assets/generated/calendar-$strip.png']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: CalendarMotion(kind: kind)),
        ),
      );
      await tester.pump();
      double left() =>
          tester.widget<RasterSprite>(find.byType(RasterSprite)).source.left;
      expect(left(), 0);
      // Simulate three timer intervals while the next UI frame is delayed.
      // A child must still see pose1 before poses2 and3 when drawing resumes.
      await tester.pump(const Duration(milliseconds: 960));
      expect(left(), .25);
      await tester.pump(const Duration(milliseconds: 320));
      expect(left(), kind == 'extra' ? 730 / 1536 : .5);
      await tester.pump(const Duration(milliseconds: 320));
      expect(left(), kind == 'extra' ? 1190 / 1536 : .75);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
}
