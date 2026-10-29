import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/engagement/ray_raid_model.dart';
import 'package:mykids_family/engagement/ray_raid_painter.dart';

// Raster checks run in the Windows test engine, without any Android device.
void main() {
  if (!Platform.isWindows) {
    throw StateError('Use the Windows test engine only');
  }
  const size = Size(360, 500);

  Future<Set<int>> arrows(
    RayRaidWorld world,
    RayRaidArt art,
    ValueNotifier<int> frames,
    Rect area,
    double time, {
    bool calm = false,
  }) async {
    world.elapsed = time;
    final recorder = ui.PictureRecorder();
    RayRaidPainter(
      world: world,
      art: art,
      frames: frames,
      calmEffects: calm,
    ).paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null) throw StateError('Missing rendered pixels');
    final camera = RaidCamera.forWorld(size, world);
    final region = Rect.fromPoints(
      camera.point(RaidVec(area.left, area.top)),
      camera.point(RaidVec(area.right, area.bottom)),
    );
    final mask = <int>{};
    for (var y = region.top.ceil(); y < region.bottom.floor(); y++) {
      for (var x = region.left.ceil(); x < region.right.floor(); x++) {
        final index = y * size.width.toInt() + x;
        final offset = index * 4;
        if (bytes.getUint8(offset) < 170 &&
            bytes.getUint8(offset + 1) > 190 &&
            bytes.getUint8(offset + 2) > 220) {
          mask.add(index);
        }
      }
    }
    return mask;
  }

  for (final profile in [
    (
      name: 'left',
      player: const RaidVec(560, 1320),
      area: const Rect.fromLTRB(330, 1314, 480, 1342),
      vertical: false,
      sign: -1,
    ),
    (
      name: 'up',
      player: const RaidVec(950, 1000),
      area: const Rect.fromLTRB(936, 840, 964, 930),
      vertical: true,
      sign: -1,
    ),
    (
      name: 'right',
      player: const RaidVec(560, 520),
      area: const Rect.fromLTRB(330, 521, 480, 549),
      vertical: false,
      sign: 1,
    ),
  ]) {
    testWidgets(
      'rendered conveyor arrows move ${profile.name} with their force',
      (tester) async {
        final art = await tester.runAsync(RayRaidArt.load);
        expect(art, isNotNull);
        final frames = ValueNotifier(0);
        final world = RayRaidWorld(mission: RaidMission.magnet)
          ..start()
          ..player = profile.player;
        try {
          final masks = await tester.runAsync(
            () async => (
              await arrows(world, art!, frames, profile.area, .5),
              await arrows(world, art, frames, profile.area, .6),
            ),
          );
          final (before, after) = masks!;
          expect(before.length, greaterThan(10));
          expect(after.length, greaterThan(10));
          var bestOffset = 0, bestOverlap = -1;
          for (var delta = -4; delta <= 4; delta++) {
            final shift = profile.vertical ? delta * size.width.toInt() : delta;
            final overlap = before
                .where((pixel) => after.contains(pixel + shift))
                .length;
            if (overlap > bestOverlap) {
              bestOffset = delta;
              bestOverlap = overlap;
            }
          }
          expect(bestOverlap, greaterThan(before.length * .45));
          expect(
            bestOffset * profile.sign,
            greaterThan(0),
            reason: 'Actual cyan pixels must follow the same direction as the belt force',
          );
        } finally {
          art!.dispose();
          frames.dispose();
        }
      },
    );
  }

  testWidgets('quiet effects keep the rendered conveyor arrows still', (
    tester,
  ) async {
    final art = await tester.runAsync(RayRaidArt.load);
    final frames = ValueNotifier(0);
    final world = RayRaidWorld(mission: RaidMission.magnet)..start();
    try {
      const area = Rect.fromLTRB(330, 1314, 480, 1342);
      final masks = await tester.runAsync(
        () async => (
          await arrows(world, art!, frames, area, .5, calm: true),
          await arrows(world, art, frames, area, .6, calm: true),
        ),
      );
      final (before, after) = masks!;
      expect(before.length, greaterThan(10));
      expect(after, equals(before));
    } finally {
      art!.dispose();
      frames.dispose();
    }
  });
}
