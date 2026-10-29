import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_art.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = <String, ByteData>{};
  setUpAll(() async {
    await precacheRasterArtwork([GameDesign.all.first.animation]);
    for (final design in GameDesign.all.skip(1)) {
      bytes[design.animation] = await rootBundle.load(design.animation);
    }
  });
  for (final selected in GameDesign.all.skip(1)) {
    testWidgets('${selected.id}: cold artwork paints pose zero before moving', (
      tester,
    ) async {
      gameDesign.value = GameDesign.all.first;
      final messenger = tester.binding.defaultBinaryMessenger;
      final gate = Completer<ByteData?>();
      Widget scene(String hero) => MaterialApp(
        home: Scaffold(body: EngagementAvatar(hero: hero)),
      );
      Rect pose() => tester
          .widgetList<RasterSprite>(find.byType(RasterSprite))
          .single
          .source;
      try {
        await tester.pumpWidget(scene('blocks'));
        await tester.pump(const Duration(milliseconds: 320));
        messenger.setMockMessageHandler('flutter/assets', (message) {
          final path = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          return path == selected.animation
              ? gate.future
              : messenger.delegate.send('flutter/assets', message);
        });
        await tester.pumpWidget(scene(selected.id));
        await tester.pump(const Duration(milliseconds: 480));
        expect(
          pose(),
          const Rect.fromLTWH(0, 0, 1 / 3, .5),
          reason: 'Loading an atlas must not consume its greeting frames.',
        );
        gate.complete(bytes[selected.animation]);
        final painted = find.descendant(
          of: find.byType(RasterSprite),
          matching: find.byType(CustomPaint),
        );
        for (var i = 0; i < 100 && painted.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(painted, findsOneWidget);
        expect(pose(), const Rect.fromLTWH(0, 0, 1 / 3, .5));
        for (final frame in [1, 2, 3, 2, 1, 0]) {
          await tester.pump(const Duration(milliseconds: 160));
          expect(
            pose(),
            Rect.fromLTWH(frame % 3 / 3, frame ~/ 3 / 2, 1 / 3, .5),
          );
        }
      } finally {
        if (!gate.isCompleted) gate.complete(bytes[selected.animation]);
        await tester.pumpWidget(const SizedBox.shrink());
        messenger.setMockMessageHandler('flutter/assets', null);
        gameDesign.value = null;
      }
    });
  }
}
