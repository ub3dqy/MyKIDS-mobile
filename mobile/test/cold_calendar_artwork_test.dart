import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/morning.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final artwork = <String, ByteData>{};
  setUpAll(() async {
    for (final strip in ['book', 'extra', 'task']) {
      final path = 'assets/generated/calendar-$strip.png';
      artwork[path] = await rootBundle.load(path);
    }
  });
  for (final (kind, strip) in [
    ('school', 'book'),
    ('extra', 'extra'),
    ('task', 'task'),
  ]) {
    testWidgets('$kind: first loading preserves all four morning poses', (
      tester,
    ) async {
      final path = 'assets/generated/calendar-$strip.png';
      final bytes = artwork[path]!;
      final messenger = tester.binding.defaultBinaryMessenger;
      final gate = Completer<ByteData?>();
      gameDesign.value = GameDesign.all.first;
      messenger.setMockMessageHandler('flutter/assets', (message) {
        final requested = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        return requested == path
            ? gate.future
            : messenger.delegate.send('flutter/assets', message);
      });
      Rect pose() =>
          tester.widget<RasterSprite>(find.byType(RasterSprite)).source;
      Widget scene({bool enabled = true}) => MaterialApp(
        home: TickerMode(
          enabled: enabled,
          child: Scaffold(body: CalendarMotion(kind: kind)),
        ),
      );
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(scene());
        final first = pose();
        await tester.pump(const Duration(milliseconds: 960));
        expect(
          pose(),
          first,
          reason: 'The helper cannot spend its gesture while its picture is loading.',
        );
        if (kind == 'extra') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
        } else if (kind == 'task') {
          await tester.pumpWidget(scene(enabled: false));
        }
        gate.complete(bytes);
        final painted = find.descendant(
          of: find.byType(RasterSprite),
          matching: find.byType(CustomPaint),
        );
        for (
          var attempt = 0;
          attempt < 100 && !rasterArtworkIsReady(path);
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(rasterArtworkIsReady(path), isTrue);
        expect(pose(), first);
        if (kind != 'school') {
          await tester.pump(const Duration(milliseconds: 960));
          expect(
            pose(),
            first,
            reason: 'A late image must not restart a hidden helper.',
          );
          if (kind == 'extra') {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pump();
          } else {
            await tester.pumpWidget(scene());
          }
        }
        expect(painted, findsOneWidget);
        const extraEdges = [0.0, 384.0, 730.0, 1190.0, 1536.0];
        for (final frame in [1, 2, 3]) {
          await tester.pump(const Duration(milliseconds: 320));
          final left = strip == 'extra' ? extraEdges[frame] / 1536 : frame / 4;
          final width = strip == 'extra'
              ? (extraEdges[frame + 1] - extraEdges[frame]) / 1536
              : .25;
          expect(pose(), Rect.fromLTWH(left, .1, width, .82));
        }
        final last = pose();
        await tester.pump(const Duration(milliseconds: 640));
        expect(pose(), last);
      } finally {
        if (!gate.isCompleted) gate.complete(bytes);
        await tester.pumpWidget(const SizedBox.shrink());
        messenger.setMockMessageHandler('flutter/assets', null);
        gameDesign.value = null;
      }
      expect(tester.takeException(), isNull);
    });
  }
}
