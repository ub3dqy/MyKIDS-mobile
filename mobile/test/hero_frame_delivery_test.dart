import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/child_visuals.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_art.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  for (final design in GameDesign.all) {
    for (final celebrate in [false, true]) {
      for (final engagement in [false, true]) {
        testWidgets(
          '${design.id}: ${engagement ? 'hero' : 'helper'} '
          '${celebrate ? 'reward' : 'greeting'} keeps every pose after a slow frame',
          (tester) async {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.runAsync(
              () => precacheRasterArtwork([design.animation]),
            );
            gameDesign.value = design;
            try {
              await tester.pumpWidget(
                MaterialApp(
                  home: Scaffold(
                    body: engagement
                        ? EngagementAvatar(
                            hero: design.id,
                            celebrate: celebrate,
                          )
                        : ChildMotion(celebrate: celebrate),
                  ),
                ),
              );
              Rect pose() => tester
                  .widget<RasterSprite>(find.byType(RasterSprite))
                  .source;
              expect(pose(), const Rect.fromLTWH(0, 0, 1 / 3, .5));
              final sequence = celebrate ? [1, 2, 3, 4, 5] : [1, 2, 3, 2, 1];
              for (final frame in sequence) {
                // Three timer intervals elapse before Android draws again.
                // Each authored pose must still reach the next visible frame.
                await tester.pump(const Duration(milliseconds: 480));
                expect(
                  pose(),
                  Rect.fromLTWH(frame % 3 / 3, frame ~/ 3 / 2, 1 / 3, .5),
                );
              }
              // A queued post-paint callback must not restart a hidden hero.
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
              await tester.pump();
              final paused = pose();
              await tester.pump(const Duration(seconds: 2));
              expect(pose(), paused);
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
              await tester.pump();
              final approved = celebrate
                  ? [0, 1, 2, 3, 4, 5]
                  : [0, 1, 2, 3, 2, 1];
              // At normal drawing speed retain the agreed 160ms poses,
              // quiet hold and 4.8s loop, rather than slowing every cycle.
              for (var step = 1; step <= 31; step++) {
                await tester.pump(const Duration(milliseconds: 160));
                final tick = step % 30;
                final frame = tick < approved.length
                    ? approved[tick]
                    : celebrate
                    ? 5
                    : 0;
                expect(
                  pose(),
                  Rect.fromLTWH(frame % 3 / 3, frame ~/ 3 / 2, 1 / 3, .5),
                );
              }
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              gameDesign.value = null;
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
