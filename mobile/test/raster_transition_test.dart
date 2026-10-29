import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_art.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  setUpAll(() async {
    await precacheRasterArtwork(GameDesign.all.map((d) => d.animation));
    await precacheRasterArtwork(['assets/generated/calendar-book.png']);
  });
  Future<void> decoded(WidgetTester tester) async {
    final futures = tester
        .widgetList<FutureBuilder<ui.Image>>(
          find.byWidgetPredicate((w) => w is FutureBuilder<ui.Image>),
        )
        .map((w) => w.future!)
        .toList();
    await tester.runAsync(() => Future.wait(futures));
    await tester.pump();
  }

  testWidgets('a reused sprite never paints the previous world while loading', (
    tester,
  ) async {
    const first = 'assets/generated/calendar-book.png';
    const second = 'assets/generated/calendar-task.png';
    Widget scene(String path) => MaterialApp(
      home: Center(
        child: RasterSprite(
          path: path,
          normalized: true,
          source: const Rect.fromLTWH(0, 0, 1 / 3, .5),
          size: 160,
        ),
      ),
    );
    final paint = find.descendant(
      of: find.byType(RasterSprite),
      matching: find.byType(CustomPaint),
    );
    await tester.pumpWidget(scene(first));
    await decoded(tester);
    expect(paint, findsOneWidget);
    await tester.pumpWidget(scene(second));
    final staleImagePainted = paint.evaluate().isNotEmpty;
    await decoded(tester);
    expect(paint, findsOneWidget);
    expect(
      staleImagePainted,
      isFalse,
      reason:
          'The old world must disappear as soon as the new one is selected.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('all five worlds replace the decoded sprite without stale data', (
    tester,
  ) async {
    Widget scene(String hero) =>
        MaterialApp(home: EngagementAvatar(hero: hero));
    final paint = find.descendant(
      of: find.byType(RasterSprite),
      matching: find.byType(CustomPaint),
    );
    for (final from in GameDesign.all) {
      for (final to in GameDesign.all.where((d) => d.id != from.id)) {
        await tester.pumpWidget(scene(from.id));
        await decoded(tester);
        final previous = tester.widget<CustomPaint>(paint).painter!;
        await tester.pumpWidget(scene(to.id));
        expect(
          paint,
          findsOneWidget,
          reason: 'Decoded art needs no empty frame.',
        );
        expect(
          tester.widget<CustomPaint>(paint).painter!.shouldRepaint(previous),
          isTrue,
          reason: '${from.id} → ${to.id} must not paint the previous world.',
        );
        await decoded(tester);
        expect(paint, findsOneWidget);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing sprite fitting invalidates its previous painting', (
    tester,
  ) async {
    Widget scene(bool fitted) => MaterialApp(
      home: RasterSprite(
        path: GameDesign.all.first.animation,
        normalized: true,
        source: const Rect.fromLTWH(0, 0, 1 / 3, .5),
        preserveAspectRatio: fitted,
      ),
    );
    final paint = find.descendant(
      of: find.byType(RasterSprite),
      matching: find.byType(CustomPaint),
    );
    await tester.pumpWidget(scene(false));
    await decoded(tester);
    final previous = tester.widget<CustomPaint>(paint).painter!;
    await tester.pumpWidget(scene(true));
    expect(
      tester.widget<CustomPaint>(paint).painter!.shouldRepaint(previous),
      isTrue,
      reason:
          'A changed image fit must be visible without another animation tick.',
    );
    expect(tester.takeException(), isNull);
  });
}
