import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_pages.dart';
import 'package:mykids_family/engagement/engagement_scope.dart';
import 'package:mykids_family/engagement/preview_controller.dart';
import 'package:mykids_family/engagement/production_controller.dart';

import 'engagement_layout_test.dart' as agreed;
import 'support/engagement_fixture.dart';

void main() {
  testWidgets('Android system panels preserve the approved room sheet height', (
    tester,
  ) async {
    final preview = PreviewEngagementController(
      EngagementReviewRepository(),
      save: (_) async {},
    );
    final repo = ProductionFixtureRepository(preview);
    final c = ProductionEngagementController(repo);
    gameDesign.value = GameDesign.all.first;
    final heights = <double>[];
    try {
      for (final inset in [0.0, 24.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(412, 915 + inset * 2);
        tester.view.padding = FakeViewPadding(top: inset, bottom: inset);
        tester.view.viewPadding = FakeViewPadding(top: inset, bottom: inset);
        await tester.pumpWidget(
          MaterialApp(
            theme: gameDesign.value!.theme(true),
            builder: (_, child) =>
                EngagementScope(controller: c, child: child!),
            home: const RoomPage(),
          ),
        );
        await agreed.artwork(tester);
        roomItemsSheet(tester.element(find.byType(RoomPage)), 0);
        await tester.pumpAndSettle();
        await agreed.artwork(tester);
        heights.add(tester.getSize(find.byType(ListView).last).height);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(heights[1], closeTo(heights[0], .01));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      c.dispose();
      repo.dispose();
      repo.client.close();
      preview.dispose();
      gameDesign.value = null;
    }
  });
}
