import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_art.dart';
import 'package:mykids_family/morning.dart';
import 'package:mykids_family/visuals.dart';

import 'calendar_test.dart' as fixture;

void main() {
  setUpAll(
    () => precacheRasterArtwork([
      for (final design in GameDesign.all) design.animation,
      for (final kind in ['book', 'extra', 'task'])
        'assets/generated/calendar-$kind.png',
    ]),
  );
  tearDown(() => gameDesign.value = null);

  for (final design in GameDesign.all) {
    testWidgets('${design.id}: a newly chosen hero starts its full gesture', (
      tester,
    ) async {
      gameDesign.value = design;
      Widget scene(String hero) => MaterialApp(
        home: Scaffold(body: EngagementAvatar(hero: hero)),
      );
      Rect pose() => tester
          .widgetList<RasterSprite>(find.byType(RasterSprite))
          .single
          .source;

      for (final selected in GameDesign.all) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(scene('auto'));
        await tester.pump(const Duration(milliseconds: 160));
        expect(pose(), const Rect.fromLTWH(1 / 3, 0, 1 / 3, .5));
        await tester.pump(const Duration(milliseconds: 160));
        expect(pose(), const Rect.fromLTWH(2 / 3, 0, 1 / 3, .5));

        await tester.pumpWidget(scene(selected.id));
        expect(
          pose(),
          const Rect.fromLTWH(0, 0, 1 / 3, .5),
          reason: 'The new hero must not inherit the previous hero gesture.',
        );
        for (final frame in [1, 2, 3, 2, 1, 0]) {
          await tester.pump(const Duration(milliseconds: 160));
          expect(
            pose(),
            Rect.fromLTWH(frame % 3 / 3, frame ~/ 3 / 2, 1 / 3, .5),
          );
        }

        await tester.pumpWidget(scene('auto'));
        expect(pose(), const Rect.fromLTWH(0, 0, 1 / 3, .5));
        await tester.pump(const Duration(milliseconds: 160));
        expect(pose(), const Rect.fromLTWH(1 / 3, 0, 1 / 3, .5));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    for (final kind in ['school', 'extra', 'task']) {
      testWidgets(
        '${design.id}: consecutive $kind activities replay their helper',
        (tester) async {
          gameDesign.value = design;
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final entries = calendarDay(
            fixture.snapshot([
              fixture.event('Первое дело', '08:00', '09:00', kind: kind),
              fixture.event('Второе дело', '10:00', '11:00', kind: kind),
            ]),
            DateTime.utc(2026, 10, 12, 12),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: design.theme(true),
              home: Scaffold(
                body: MorningOverview(entries: entries, dayLabel: '12.10'),
              ),
            ),
          );
          Rect pose() => tester
              .widget<RasterSprite>(
                find.descendant(
                  of: find.byType(CalendarMotion),
                  matching: find.byType(RasterSprite),
                ),
              )
              .source;
          final initial = pose();
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 320));
          }
          expect(pose(), isNot(initial));
          await tester.tap(find.text('Дальше'));
          await tester.pump();
          expect(find.text('2 из 2'), findsOneWidget);
          expect(
            pose(),
            initial,
            reason: 'Every new activity must start the approved gesture.',
          );
          await tester.pump(const Duration(milliseconds: 320));
          expect(pose(), isNot(initial));
          await tester.tap(find.text('Назад'));
          await tester.pump();
          expect(find.text('1 из 2'), findsOneWidget);
          expect(pose(), initial);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
