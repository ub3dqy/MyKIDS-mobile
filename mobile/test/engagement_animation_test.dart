import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_art.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  setUpAll(
    () =>
        precacheRasterArtwork(GameDesign.all.map((design) => design.animation)),
  );
  for (final design in GameDesign.all) {
    testWidgets(
      '${design.id}: six real sprite poses, idle pause and reduced motion',
      (tester) async {
        gameDesign.value = design;
        var reduced = false;
        Widget scene() => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const EngagementAvatar(
              hero: 'auto',
              worn: {'badge', 'cape', 'headphones'},
            ),
          ),
        );
        Rect pose() => tester
            .widgetList<RasterSprite>(find.byType(RasterSprite))
            .singleWhere((s) => s.path == design.animation)
            .source;
        await tester.pumpWidget(scene());
        for (final frame in [0, 1, 2, 3, 2, 1, 0]) {
          expect(
            pose(),
            Rect.fromLTWH(frame % 3 / 3, frame ~/ 3 / 2, 1 / 3, .5),
          );
          await tester.pump(const Duration(milliseconds: 160));
        }
        expect(
          tester.widgetList<PlayItemArt>(find.byType(PlayItemArt)).length,
          3,
        );
        reduced = true;
        await tester.pumpWidget(scene());
        final still = pose();
        await tester.pump(const Duration(seconds: 2));
        expect(pose(), still);
        reduced = false;
        await tester.pumpWidget(scene());
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 2));
        expect(pose(), still);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 160));
        expect(pose(), isNot(still));
        await tester.pumpWidget(const SizedBox.shrink());
        gameDesign.value = null;
        expect(tester.takeException(), isNull);
      },
    );
  }
}
