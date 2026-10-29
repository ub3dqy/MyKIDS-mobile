import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
  });
  tearDown(() => gameDesign.value = null);
  for (final design in GameDesign.all) {
    testWidgets('${design.id}: illustrated greeting keeps readable contrast', (
      tester,
    ) async {
      gameDesign.value = design;
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final surface = GlobalKey();
      const title = 'Привет, Саша!';
      const description = 'Вперёд к открытиям!';
      Widget scene(bool text) => MaterialApp(
        theme: design.theme(true),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: surface,
              child: SizedBox(
                width: 380,
                child: GameScene(
                  title: text ? title : '',
                  description: text ? description : '',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene(true));
      await tester.runAsync(
        () => precacheImage(
          AssetImage(design.scene),
          tester.element(find.byType(GameScene)),
        ),
      );
      await tester.pump();
      final boundary =
          surface.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final originalSize = boundary.size;
      final spans =
          <({String text, Offset origin, Size size, TextSpan span})>[];
      for (final label in [title, description]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        spans.add((
          text: label,
          origin: paragraph.localToGlobal(Offset.zero, ancestor: boundary),
          size: paragraph.size,
          span: paragraph.text as TextSpan,
        ));
      }
      final actual = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        try {
          return Uint8List.fromList(
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
                .asUint8List(),
          );
        } finally {
          image.dispose();
        }
      }))!;
      await tester.pumpWidget(scene(false));
      await tester.pump();
      expect(boundary.size, originalSize);
      final minima = <double>[];
      await tester.runAsync(() async {
        final background = await boundary.toImage(pixelRatio: 3);
        try {
          final pixels = (await background.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          for (final text in spans) {
            final style = text.span.style!;
            final foreground = style.color!;
            final painter = TextPainter(
              text: TextSpan(
                text: text.text,
                style: style.copyWith(color: Colors.white),
              ),
              textDirection: TextDirection.ltr,
              maxLines: text.text == title ? 3 : 4,
              ellipsis: '…',
            )..layout(maxWidth: text.size.width);
            final recorder = ui.PictureRecorder();
            painter.paint(Canvas(recorder)..scale(3), Offset.zero);
            final picture = recorder.endRecording();
            final mask = await picture.toImage(
              (text.size.width * 3).ceil(),
              (text.size.height * 3).ceil(),
            );
            try {
              final glyph = (await mask.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              var minimum = double.infinity, visible = 0, matched = 0;
              for (var y = 0; y < mask.height; y++) {
                for (var x = 0; x < mask.width; x++) {
                  if (glyph[(y * mask.width + x) * 4 + 3] < 250) continue;
                  final at =
                      (((text.origin.dy * 3).round() + y) * background.width +
                          (text.origin.dx * 3).round() +
                          x) *
                      4;
                  final backdrop = Color.fromARGB(
                    255,
                    pixels[at],
                    pixels[at + 1],
                    pixels[at + 2],
                  );
                  final color = foreground.toARGB32();
                  if ((actual[at] - ((color >> 16) & 255)).abs() <= 4 &&
                      (actual[at + 1] - ((color >> 8) & 255)).abs() <= 4 &&
                      (actual[at + 2] - (color & 255)).abs() <= 4) {
                    matched++;
                  }
                  final a = foreground.computeLuminance();
                  final b = backdrop.computeLuminance();
                  minimum = math.min(
                    minimum,
                    (math.max(a, b) + .05) / (math.min(a, b) + .05),
                  );
                  visible++;
                }
              }
              expect(visible, greaterThan(100));
              debugPrint(
                '${design.id}: glyph raster agreement ${matched / visible}',
              );
              expect(
                matched / visible,
                greaterThan(.75),
                reason:
                    'Contrast samples must coincide with actual painted text',
              );
              minima.add(minimum);
            } finally {
              mask.dispose();
              picture.dispose();
              painter.dispose();
            }
          }
        } finally {
          background.dispose();
        }
      });
      debugPrint(
        '${design.id}: heading ${minima[0]}, description ${minima[1]}',
      );
      // Use the body-text contrast threshold for children's headings as well.
      expect(minima[0], greaterThanOrEqualTo(4.5));
      expect(minima[1], greaterThanOrEqualTo(4.5));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
