import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/child_visuals.dart';
import 'package:mykids_family/design_preferences.dart';
import 'package:mykids_family/design_review.dart'
    show ReviewBackground, ReviewUpdates;
import 'package:mykids_family/design_review_control.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_art.dart';
import 'package:mykids_family/engagement/engagement_entries.dart';
import 'package:mykids_family/engagement/preview_controller.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/visuals.dart';

import 'support/engagement_fixture.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  tearDown(() => gameDesign.value = null);

  testWidgets('the saved world updates actual settings artwork and card palette', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final initial in GameDesign.all) {
      gameDesign.value = initial;
      final preview = PreviewEngagementController(
        EngagementReviewRepository(),
        save: (_) async {},
      );
      final repo = ProductionFixtureRepository(preview);
      final preferences = DesignPreferences(
        read: () async => initial.id,
        write: (_) async {},
      );
      final pages = ReviewPageSelection();
      await tester.pumpWidget(
        MyKidsApp(
          repository: repo,
          pageSelection: pages,
          designPreferences: preferences,
          createBackground: ReviewBackground.new,
          createUpdates: ReviewUpdates.new,
        ),
      );
      await frames(tester);
      pages.select(5);
      await frames(tester);
      final stillHero = find.descendant(
        of: find.byType(HeroHomeActions),
        matching: find.byType(EngagementAvatar),
      );
      expect(stillHero, findsOneWidget);
      for (final selected in GameDesign.all) {
        await preferences.select(selected);
        await tester.pump();
        final sprite = tester
            .widgetList<RasterSprite>(
              find.descendant(
                of: stillHero,
                matching: find.byType(RasterSprite),
              ),
            )
            .singleWhere(
              (s) => GameDesign.all.any((d) => s.path == d.animation),
            );
        expect(
          sprite.path,
          selected.animation,
          reason:
              '${initial.id} → ${selected.id}: settings must use the saved world immediately',
        );
        for (final entry in [
          find.byType(AdventureEntry),
          find.byType(FamilyMissionEntry),
        ]) {
          expect(entry, findsOneWidget);
          final card = tester.widget<Card>(
            find.descendant(of: entry, matching: find.byType(Card)),
          );
          expect(
            card.color,
            selected.soft,
            reason:
                '${initial.id} → ${selected.id}: profile cards must use the saved palette immediately',
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      preview.dispose();
      repo.client.close();
      repo.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'a mounted automatic avatar follows all worlds; reduced=$reduced',
      (tester) async {
        gameDesign.value = GameDesign.all.first;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: const EngagementAvatar(hero: 'auto', animate: false),
            ),
          ),
        );
        for (final selected in GameDesign.all.reversed) {
          gameDesign.value = selected;
          await tester.pump();
          expect(
            tester.widget<RasterSprite>(find.byType(RasterSprite)).path,
            selected.animation,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a reduced-motion helper follows live worlds without a timer', (
    tester,
  ) async {
    gameDesign.value = GameDesign.all.first;
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: ChildMotion(),
        ),
      ),
    );
    for (final selected in GameDesign.all.reversed) {
      gameDesign.value = selected;
      await tester.pump();
      expect(
        tester.widget<RasterSprite>(find.byType(RasterSprite)).path,
        selected.animation,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing the world preserves an explicitly chosen hero and pose',
    (tester) async {
      gameDesign.value = GameDesign.all.first;
      await tester.pumpWidget(
        const MaterialApp(home: EngagementAvatar(hero: 'comic')),
      );
      await tester.pump(const Duration(milliseconds: 320));
      final initial = tester.widget<RasterSprite>(find.byType(RasterSprite));
      for (final selected in GameDesign.all) {
        gameDesign.value = selected;
        await tester.pump();
        final sprite = tester.widget<RasterSprite>(find.byType(RasterSprite));
        expect(sprite.path, initial.path);
        expect(sprite.source, initial.source);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      gameDesign.value = GameDesign.all.first;
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
