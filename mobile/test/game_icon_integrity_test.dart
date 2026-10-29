import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';

const atlas = 'assets/designs/game-icons.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all thirty animation frames have clear borders and complete figures',
    () async {
      for (final design in GameDesign.all) {
        final data = await rootBundle.load(design.animation);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final image = (await codec.getNextFrame()).image;
        try {
          expect(image.width, 1536);
          expect(image.height, 1024);
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          for (var frame = 0; frame < 6; frame++) {
            var opaque = 0;
            for (var y = 0; y < 512; y++) {
              for (var x = 0; x < 512; x++) {
                final at =
                    ((frame ~/ 3 * 512 + y) * image.width +
                            frame % 3 * 512 +
                            x) *
                        4 +
                    3;
                final alpha = pixels[at];
                if (x == 0 || y == 0 || x == 511 || y == 511) {
                  expect(
                    alpha,
                    lessThanOrEqualTo(4),
                    reason:
                        '${design.id} frame $frame has a rectangular border',
                  );
                }
                if (alpha >= 200) {
                  opaque++;
                  expect(
                    x,
                    inInclusiveRange(8, 503),
                    reason:
                        '${design.id} frame $frame cuts a figure horizontally',
                  );
                  expect(
                    y,
                    inInclusiveRange(8, 503),
                    reason:
                        '${design.id} frame $frame cuts a figure vertically',
                  );
                }
              }
            }
            expect(
              opaque,
              greaterThan(20000),
              reason: '${design.id} frame $frame is missing its figure',
            );
          }
        } finally {
          image.dispose();
          codec.dispose();
        }
      }
    },
  );

  test(
    'every complete authored subject fits its crop without another icon',
    () async {
      final data = await rootBundle.load(atlas);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      try {
        expect(
          Size(image.width.toDouble(), image.height.toDouble()),
          GameIcon.atlasSize,
        );
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final visited = Uint8List(image.width * image.height);
        final queue = Int32List(visited.length);
        final subjects = <Rect>[];
        // Discover the subjects from actual opaque connected artwork pixels,
        // independently of the renderer's rectangle definitions.
        for (var start = 0; start < visited.length; start++) {
          if (visited[start] != 0 || pixels[start * 4 + 3] < 32) continue;
          var head = 0, tail = 0;
          queue[tail++] = start;
          visited[start] = 1;
          var left = image.width, top = image.height, right = 0, bottom = 0;
          while (head < tail) {
            final at = queue[head++];
            final x = at % image.width, y = at ~/ image.width;
            if (x < left) left = x;
            if (y < top) top = y;
            if (x + 1 > right) right = x + 1;
            if (y + 1 > bottom) bottom = y + 1;
            for (final next in [
              if (x > 0) at - 1,
              if (x + 1 < image.width) at + 1,
              if (y > 0) at - image.width,
              if (y + 1 < image.height) at + image.width,
            ]) {
              if (visited[next] == 0 && pixels[next * 4 + 3] >= 32) {
                visited[next] = 1;
                queue[tail++] = next;
              }
            }
          }
          if (tail > 4000) {
            subjects.add(
              Rect.fromLTRB(
                left.toDouble(),
                top.toDouble(),
                right.toDouble(),
                bottom.toDouble(),
              ),
            );
          }
        }
        subjects.sort((a, b) {
          final rowA = (a.center.dy / (image.height / 3)).floor();
          final rowB = (b.center.dy / (image.height / 3)).floor();
          return rowA == rowB ? a.left.compareTo(b.left) : rowA.compareTo(rowB);
        });
        expect(subjects, hasLength(12));
        expect(GameIcon.sources, hasLength(subjects.length));
        for (var index = 0; index < subjects.length; index++) {
          final crop = GameIcon.sources[index];
          final completeOutline = subjects[index].inflate(2);
          expect(
            crop.intersect(completeOutline),
            completeOutline,
            reason: 'Icon $index must retain its complete outline',
          );
          for (var other = 0; other < subjects.length; other++) {
            if (other == index) continue;
            expect(
              crop.overlaps(subjects[other]),
              isFalse,
              reason: 'Icon $index includes part of icon $other',
            );
          }
        }
      } finally {
        image.dispose();
        codec.dispose();
      }
    },
  );

  testWidgets(
    'tight parent constraints scale all icons instead of cutting them',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox).first);
      await tester.runAsync(
        () => precacheImage(const AssetImage(atlas), context),
      );
      final key = GlobalKey();
      Future<Uint8List> render(
        int index,
        double requested,
        double available,
      ) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox.square(
                  dimension: available,
                  child: GameIcon(index, size: requested),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          try {
            return Uint8List.fromList(
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List(),
            );
          } finally {
            image.dispose();
          }
        }))!;
      }

      for (var index = 0; index < 12; index++) {
        for (final available in [16.0, 24.0, 28.0, 32.0, 64.0]) {
          final expected = await render(index, available, available);
          final constrained = await render(index, available * 2, available);
          var different = 0, visible = 0;
          for (var byte = 0; byte < expected.length; byte++) {
            if (expected[byte] != constrained[byte]) different++;
            if (byte % 4 == 3 && expected[byte] >= 32) visible++;
          }
          expect(visible, greaterThan(20), reason: 'Icon $index is blank');
          expect(different, 0, reason: 'Icon $index is cut at ${available}px');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'settings button keeps its requested icon size and remains tappable',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: IconButton(
                iconSize: 24,
                tooltip: 'Настройки',
                onPressed: () => tapped = true,
                icon: const GameIcon(5),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(GameIcon));
      await tester.runAsync(
        () => precacheImage(const AssetImage(atlas), context),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(GameIcon)), const Size(32, 32));
      expect(find.byTooltip('Настройки'), findsOneWidget);
      await tester.tap(find.byTooltip('Настройки'));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
