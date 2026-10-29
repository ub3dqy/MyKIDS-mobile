import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ray_raid_model.dart';

class RayRaidArt {
  final ui.Image floor, sprites;
  final ui.Image? operations, portals, rescue;
  RayRaidArt(
    this.floor,
    this.sprites, [
    this.operations,
    this.portals,
    this.rescue,
  ]);
  static Future<ui.Image> _image(String name) async {
    final data = await rootBundle.load('assets/raid/$name');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static Future<RayRaidArt> load() async {
    final floor = await _image('lunar-floor-v1.png');
    ui.Image? sprites, operations, portals;
    try {
      sprites = await _image('ray-sprites-v1.png');
      operations = await _image('ray-operations-v1.png');
      portals = await _image('ray-portal-v1.png');
      return RayRaidArt(
        floor,
        sprites,
        operations,
        portals,
        await _image('ray-rescue-v1.png'),
      );
    } catch (_) {
      floor.dispose();
      sprites?.dispose();
      operations?.dispose();
      portals?.dispose();
      rethrow;
    }
  }

  void dispose() {
    floor.dispose();
    sprites.dispose();
    operations?.dispose();
    portals?.dispose();
    rescue?.dispose();
  }
}

class RaidCamera {
  final double scale;
  final Offset origin;
  const RaidCamera(this.scale, this.origin);
  factory RaidCamera.forWorld(Size size, RayRaidWorld world) {
    final scale = (size.shortestSide / 600).clamp(.46, .8).toDouble();
    final width = size.width / scale, height = size.height / scale;
    final x = (world.player.x - width / 2).clamp(
      0.0,
      math.max(0.0, raidWorldWidth - width),
    );
    final y = (world.player.y - height * .58).clamp(
      -240.0,
      math.max(-240.0, raidWorldHeight - height + 300),
    );
    return RaidCamera(scale, Offset(x.toDouble(), y.toDouble()));
  }
  Offset point(RaidVec v) =>
      Offset((v.x - origin.dx) * scale, (v.y - origin.dy) * scale);
}

class RayRaidPainter extends CustomPainter {
  final RayRaidWorld world;
  final RayRaidArt art;
  final bool calmEffects;
  RayRaidPainter({
    required this.world,
    required this.art,
    required Listenable frames,
    this.calmEffects = false,
  }) : super(repaint: frames);

  static const cyan = Color(0xff66efff), orange = Color(0xffffba55);
  final _paint = Paint()..filterQuality = FilterQuality.low;

  void sprite(
    Canvas canvas,
    int index,
    Offset center,
    Size size, {
    bool flip = false,
    double opacity = 1,
  }) {
    final source = Rect.fromLTWH(
      index % 3 * 512.0,
      index ~/ 3 * 512.0,
      512,
      512,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (flip) canvas.scale(-1, 1);
    _paint.color = Colors.white.withValues(alpha: opacity);
    canvas.drawImageRect(
      art.sprites,
      source,
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width,
        height: size.height,
      ),
      _paint,
    );
    canvas.restore();
  }

  void operationSprite(
    Canvas canvas,
    int index,
    Offset center,
    double size, {
    double opacity = 1,
    bool portal = false,
    bool rescue = false,
  }) {
    final atlas = rescue
        ? art.rescue
        : portal
        ? art.portals
        : art.operations;
    if (atlas == null) return;
    final cellWidth = atlas.width / 2, cellHeight = atlas.height / 2;
    canvas.drawImageRect(
      atlas,
      Rect.fromLTWH(
        index % 2 * cellWidth,
        index ~/ 2 * cellHeight,
        cellWidth,
        cellHeight,
      ),
      Rect.fromCenter(center: center, width: size, height: size),
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Colors.white.withValues(alpha: opacity),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final camera = RaidCamera.forWorld(size, world);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (!calmEffects && world.damageFlash > 0) {
      canvas.translate(
        math.sin(world.elapsed * 72) * 2.0,
        math.cos(world.elapsed * 61) * 1.5,
      );
    }
    canvas.scale(camera.scale);
    canvas.translate(-camera.origin.dx, -camera.origin.dy);
    final worldRect = const Rect.fromLTWH(
      0,
      0,
      raidWorldWidth,
      raidWorldHeight,
    );
    _paint.color = Colors.white;
    canvas.drawImageRect(
      art.floor,
      Rect.fromLTWH(
        0,
        0,
        art.floor.width.toDouble(),
        art.floor.height.toDouble(),
      ),
      worldRect,
      _paint,
    );
    if (world.mission != RaidMission.beacon) {
      canvas.drawRect(
        worldRect,
        Paint()
          ..color = switch (world.mission) {
            RaidMission.foundry => const Color(0x383e2211),
            RaidMission.convoy => const Color(0x3042a6c0),
            RaidMission.storm => const Color(0x38371869),
            _ => const Color(0x38271555),
          },
      );
      final deck = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = world.mission == RaidMission.foundry
            ? const Color(0x887d643c)
            : const Color(0x887e77bd);
      for (var y = 220.0; y < raidWorldHeight; y += 260) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(55, y, raidWorldWidth - 110, 130),
            const Radius.circular(20),
          ),
          deck,
        );
      }
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(worldRect.deflate(20), const Radius.circular(35)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = const Color(0xff101c30),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(worldRect.deflate(36), const Radius.circular(28)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = cyan.withValues(alpha: .23),
    );
    _beacon(canvas);
    _transport(canvas);
    _rescuePads(canvas);
    _meteorField(canvas);
    if (world.escorting) {
      final route = Path()..moveTo(raidConvoyStart.x, raidConvoyStart.y);
      for (final point in raidConvoyRoute) {
        route.lineTo(point.x, point.y);
      }
      canvas.drawPath(
        route,
        Paint()
          ..color = cyan.withValues(alpha: .1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 35
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        route,
        Paint()
          ..color = cyan.withValues(alpha: .45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    _frostField(canvas);
    for (final blast in world.blasts) {
      _blast(canvas, blast);
    }
    for (final hazard in world.hazards) {
      _hazard(canvas, hazard);
    }
    for (var i = 0; i < raidCores.length; i++) {
      final p = Offset(raidCores[i].x, raidCores[i].y);
      final found = world.collected.contains(i);
      final available =
          i == world.coreCount &&
          world.coreUnlocked &&
          world.antennaReady &&
          world.portalReady &&
          world.rescueReady &&
          (!world.escorting || world.convoyAtStop);
      final color = found
          ? cyan
          : available
          ? orange
          : const Color(0xff607c98);
      canvas.drawCircle(p, 47, Paint()..color = color.withValues(alpha: .11));
      if (world.mission == RaidMission.storm) {
        canvas.drawCircle(p, 86, Paint()..color = cyan.withValues(alpha: .07));
        canvas.drawCircle(
          p,
          86,
          Paint()
            ..color = cyan.withValues(alpha: .4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        canvas.drawArc(
          Rect.fromCircle(center: p, radius: 81),
          -math.pi / 2,
          world.antennaCharge[i] / 4 * math.pi * 2,
          false,
          Paint()
            ..color = cyan
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7,
        );
        operationSprite(
          canvas,
          3,
          p.translate(0, -12),
          125,
          opacity: found ? .7 : 1,
        );
      }
      canvas.drawCircle(
        p,
        47 + (calmEffects ? 0 : math.sin(world.elapsed * 3) * 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = found ? cyan.withValues(alpha: .35) : color,
      );
      if (!found) {
        final bob = calmEffects ? 0.0 : math.sin(world.elapsed * 2.5 + i) * 5;
        if (world.mission != RaidMission.storm) {
          sprite(
            canvas,
            3,
            p.translate(0, -12 + bob),
            const Size(88, 88),
            opacity: available ? 1 : .35,
          );
        }
      } else {
        canvas.drawPath(
          Path()
            ..moveTo(p.dx - 13, p.dy)
            ..lineTo(p.dx - 3, p.dy + 10)
            ..lineTo(p.dx + 17, p.dy - 12),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..color = cyan,
        );
      }
    }
    for (final drone in world.drones) {
      if (drone.kind == RaidDroneKind.hopper &&
          (drone.windup > 0 || drone.jumpTime > 0)) {
        final target = Offset(drone.jumpTarget.x, drone.jumpTarget.y);
        canvas.drawCircle(
          target,
          RaidBlast.radius,
          Paint()..color = const Color(0x24ff91e6),
        );
        canvas.drawCircle(
          target,
          RaidBlast.radius,
          Paint()
            ..color = const Color(0xffff91e6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
        canvas.drawLine(
          target.translate(-13, 0),
          target.translate(13, 0),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 3,
        );
        canvas.drawLine(
          target.translate(0, -13),
          target.translate(0, 13),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 3,
        );
        continue;
      }
      if (drone.windup <= 0) continue;
      final from = Offset(drone.position.x, drone.position.y);
      if (drone.kind == RaidDroneKind.pulsar) {
        canvas.drawCircle(from, 45, Paint()..color = const Color(0x3066efff));
        canvas.drawArc(
          Rect.fromCircle(center: from, radius: 49),
          -math.pi / 2,
          (1 - drone.windup / .9).clamp(0, 1) * math.pi * 2,
          false,
          Paint()
            ..color = cyan
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5,
        );
        continue;
      }
      if (drone.kind == RaidDroneKind.bomber) {
        canvas.drawCircle(
          from,
          40,
          Paint()..color = orange.withValues(alpha: .2),
        );
        continue;
      }
      for (final angle in drone.shotAngles) {
        final v = drone.aim.rotated(angle);
        final charging = drone.kind == RaidDroneKind.interceptor;
        final end = world.rayEnd(drone.position, v);
        final to = drone.kind == RaidDroneKind.prism
            ? Offset(end.x, end.y)
            : from + Offset(v.x, v.y) * (charging ? 260 : 430);
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = const Color(0xffff8c87).withValues(alpha: .55)
            ..strokeWidth = charging
                ? 48
                : drone.kind == RaidDroneKind.guardian
                ? 14
                : 8,
        );
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = const Color(0xffffc6a5)
            ..strokeWidth = 2,
        );
      }
      canvas.drawCircle(
        from,
        drone.radius + 12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xffff9887),
      );
    }
    // Depth-sort the solid cover and hovering actors so their feet stay readable.
    final drawables = <({double y, void Function() draw})>[
      for (final block in world.blocks)
        (
          y: block.y + block.height,
          draw: () {
            final center = Offset(block.center.x, block.center.y - 12);
            canvas.drawOval(
              Rect.fromCenter(
                center: center.translate(0, 30),
                width: block.width + 8,
                height: block.height * .68,
              ),
              Paint()..color = const Color(0x7707111b),
            );
            sprite(
              canvas,
              4,
              center,
              Size(block.width + 32, block.height + 65),
            );
          },
        ),
      for (final drone in world.drones)
        (y: drone.position.y, draw: () => _drone(canvas, drone)),
      (y: world.player.y, draw: () => _player(canvas)),
      if (world.escorting)
        (y: world.convoy.position.y, draw: () => _convoy(canvas)),
      if (world.upgrades[RaidUpgrade.companion]! > 0)
        (y: world.companionPosition.y, draw: () => _companion(canvas)),
      if (world.mission == RaidMission.rescue)
        for (var i = 0; i < 3; i++)
          (
            y: world.carriedRescue == i
                ? world.player.y + 1
                : world.rescuePosition(i).y,
            draw: () => _rescueRobot(canvas, i),
          ),
      if (world.upgrades[RaidUpgrade.orbit]! > 0)
        (y: world.orbitPosition.y, draw: () => _orbitGuard(canvas)),
    ]..sort((a, b) => a.y.compareTo(b.y));
    for (final drawable in drawables) {
      drawable.draw();
    }
    for (final wave in world.shockwaves) {
      final progress = 1 - wave.life / .35;
      canvas.drawCircle(
        Offset(wave.position.x, wave.position.y),
        wave.radius * (calmEffects ? .8 : progress),
        Paint()
          ..color = orange.withValues(alpha: wave.life / .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7,
      );
    }
    for (final ring in world.pulseRings) {
      final center = Offset(ring.position.x, ring.position.y);
      canvas.drawCircle(
        center,
        ring.radius,
        Paint()
          ..color = const Color(0x227edbff)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18,
      );
      canvas.drawCircle(
        center,
        ring.radius,
        Paint()
          ..color = const Color(0xff9ce6ff)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }
    for (final beam in world.beams) {
      final from = Offset(beam.from.x, beam.from.y),
          to = Offset(beam.to.x, beam.to.y);
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = const Color(0xffee88ff).withValues(alpha: .65)
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = const Color(0xffffe5ff)
          ..strokeWidth = 5,
      );
    }
    for (final arc in world.arcs) {
      final a = Offset(arc.from.x, arc.from.y), b = Offset(arc.to.x, arc.to.y);
      final delta = b - a, normal = Offset(-delta.dy, delta.dx);
      final bend = normal.distance > 0
          ? normal / normal.distance * 10
          : Offset.zero;
      final path = Path()..moveTo(a.dx, a.dy);
      for (var i = 1; i < 5; i++) {
        final at = a + delta * (i / 5) + bend * (i.isEven ? -1 : 1);
        path.lineTo(at.dx, at.dy);
      }
      path.lineTo(b.dx, b.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = cyan.withValues(alpha: arc.life / .18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    for (final bolt in world.bolts) {
      final p = Offset(bolt.position.x, bolt.position.y);
      final tail = p - Offset(bolt.velocity.x, bolt.velocity.y) * .028;
      final color = bolt.hostile ? const Color(0xffff776e) : cyan;
      if (bolt.returnOrigin != null) {
        canvas.drawArc(
          Rect.fromCircle(center: p, radius: 12),
          .4,
          4.7,
          false,
          Paint()
            ..color = const Color(0xffffb6ff)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }
      canvas.drawLine(
        tail,
        p,
        Paint()
          ..color = color.withValues(alpha: .18)
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        tail,
        p,
        Paint()
          ..color = color
          ..strokeWidth = (bolt.hostile ? 7 : 6)
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(p, 2.5, Paint()..color = Colors.white);
    }
    if (!calmEffects) {
      for (final p in world.particles) {
        final color =
            p.kind == RaidEffectKind.hit || p.kind == RaidEffectKind.drone
            ? orange
            : cyan;
        canvas.drawCircle(
          Offset(p.position.x, p.position.y),
          p.kind == RaidEffectKind.win ? 4 : 2.8,
          Paint()
            ..color = color.withValues(
              alpha: (p.life / p.duration).clamp(0, 1),
            ),
        );
      }
    }
    canvas.restore();
    _miniMap(canvas, size);
    _direction(canvas, size, camera);
    if (world.damageFlash > 0 && !calmEffects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(3),
          const Radius.circular(15),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = const Color(0xffff8e80)
              .withValues(alpha: world.damageFlash / .22 * .28),
      );
    }
  }

  void _frostField(Canvas canvas) {
    if (!world.frostActive) return;
    final center = Offset(world.player.x, world.player.y);
    canvas.drawCircle(
      center,
      world.frostRadius,
      Paint()..color = cyan.withValues(alpha: .05),
    );
    canvas.drawCircle(
      center,
      world.frostRadius,
      Paint()
        ..color = cyan.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 + (calmEffects ? 0 : world.elapsed * .15);
      final p =
          center + Offset(math.cos(angle), math.sin(angle)) * world.frostRadius;
      final paint = Paint()
        ..color = cyan
        ..strokeWidth = 2;
      canvas.drawLine(p.translate(-6, 0), p.translate(6, 0), paint);
      canvas.drawLine(p.translate(0, -6), p.translate(0, 6), paint);
    }
  }

  void _blast(Canvas canvas, RaidBlast blast) {
    final p = Offset(blast.position.x, blast.position.y), r = RaidBlast.radius;
    final color = blast.delay > 0 ? orange : const Color(0xffff8b94);
    canvas.drawCircle(
      p,
      r,
      Paint()..color = color.withValues(alpha: blast.delay > 0 ? .1 : .4),
    );
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    if (blast.delay > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: p, radius: r - 9),
        -math.pi / 2,
        (1 - blast.delay / .95) * math.pi * 2,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
    }
    canvas.drawLine(
      p.translate(-12, 0),
      p.translate(12, 0),
      Paint()
        ..color = color
        ..strokeWidth = 3,
    );
    canvas.drawLine(
      p.translate(0, -12),
      p.translate(0, 12),
      Paint()
        ..color = color
        ..strokeWidth = 3,
    );
  }

  void _convoy(Canvas canvas) {
    final p = Offset(world.convoy.position.x, world.convoy.position.y);
    canvas.drawCircle(
      p,
      210,
      Paint()
        ..color = cyan.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    operationSprite(
      canvas,
      0,
      p.translate(0, -12),
      145,
      opacity: world.convoy.immunity > 0 ? .75 : 1,
    );
    if (world.shieldTime > 0 &&
        world.shieldCharges > 0 &&
        world.player.distance(world.convoy.position) <= 210) {
      canvas.drawCircle(
        p,
        48,
        Paint()
          ..color = cyan.withValues(alpha: .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    final bar = Rect.fromLTWH(p.dx - 37, p.dy - 66, 74, 6);
    canvas.drawRect(bar, Paint()..color = const Color(0xff142738));
    canvas.drawRect(
      Rect.fromLTWH(
        bar.left,
        bar.top,
        bar.width * world.convoy.health / 8,
        bar.height,
      ),
      Paint()..color = const Color(0xff9bf1d0),
    );
  }

  void _hazard(Canvas canvas, RaidHazard hazard) {
    final p = Offset(hazard.position.x, hazard.position.y);
    final warning = world.hazardWarning(hazard),
        active = world.hazardActive(hazard);
    final color = world.hazardCooled(hazard)
        ? cyan
        : active
        ? const Color(0xffff9b49)
        : warning
        ? const Color(0xffffd27a)
        : const Color(0xff657b86);
    canvas.drawCircle(
      p,
      hazard.radius,
      Paint()..color = color.withValues(alpha: active ? .36 : .09),
    );
    canvas.drawCircle(
      p,
      hazard.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 6 : 3
        ..color = color,
    );
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(
        p.translate(-30, i * 13),
        p.translate(30, i * 13),
        Paint()
          ..color = color.withValues(alpha: .65)
          ..strokeWidth = 5,
      );
    }
    if (active) {
      canvas.drawPath(
        Path()
          ..moveTo(p.dx + 5, p.dy - 38)
          ..lineTo(p.dx - 19, p.dy + 3)
          ..lineTo(p.dx, p.dy + 3)
          ..lineTo(p.dx - 5, p.dy + 38)
          ..lineTo(p.dx + 20, p.dy - 3)
          ..lineTo(p.dx + 2, p.dy - 3)
          ..close(),
        Paint()..color = const Color(0xffffeeaa),
      );
    } else if (warning) {
      canvas.drawArc(
        Rect.fromCircle(center: p, radius: hazard.radius - 8),
        -math.pi / 2,
        (hazard.cycle(world.elapsed) - 3.8) * math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = color,
      );
    }
  }

  void _companion(Canvas canvas) {
    final p = Offset(world.companionPosition.x, world.companionPosition.y);
    canvas.drawOval(
      Rect.fromCenter(center: p.translate(0, 12), width: 40, height: 15),
      Paint()..color = const Color(0x66050b15),
    );
    canvas.drawLine(
      p.translate(-25, 0),
      p.translate(25, 0),
      Paint()
        ..color = cyan
        ..strokeWidth = 8,
    );
    canvas.drawCircle(p, 17, Paint()..color = const Color(0xffe3f9ff));
    canvas.drawCircle(p, 13, Paint()..color = const Color(0xff176a85));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: p, width: 16, height: 7),
        const Radius.circular(3),
      ),
      Paint()..color = cyan,
    );
    canvas.drawCircle(p.translate(0, 24), 4, Paint()..color = cyan);
  }

  void _player(Canvas canvas) {
    final p = Offset(world.player.x, world.player.y);
    final moving = world.movement.length > .12 || world.dashTime > 0;
    final bob = calmEffects || !moving
        ? 0.0
        : math.sin(world.elapsed * 22) * 3.5;
    canvas.drawOval(
      Rect.fromCenter(center: p.translate(0, 14), width: 63, height: 23),
      Paint()..color = const Color(0x8806101d),
    );
    if (world.dashTime > 0) {
      for (var i = 1; i < 5; i++) {
        final tail =
            p - Offset(world.dashDirection.x, world.dashDirection.y) * (i * 14);
        canvas.drawCircle(
          tail,
          24.0 - i * 3,
          Paint()..color = orange.withValues(alpha: .20 - i * .03),
        );
      }
    }
    if (world.shieldTime > 0) {
      canvas.drawCircle(
        p.translate(0, -13),
        52,
        Paint()..color = cyan.withValues(alpha: .13),
      );
      canvas.drawCircle(
        p.translate(0, -13),
        52,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 + world.upgrades[RaidUpgrade.shield]!.toDouble()
          ..color = cyan,
      );
    }
    sprite(
      canvas,
      0,
      p.translate(0, -24 + bob),
      const Size(112, 112),
      flip: world.facing.x > .2,
      opacity: world.immunity > 0 ? .78 : 1,
    );
    final muzzle = p + Offset(world.facing.x, world.facing.y) * 37;
    if (world.firing) {
      final end = p + Offset(world.facing.x, world.facing.y) * 108;
      canvas.drawLine(
        muzzle,
        end,
        Paint()
          ..color = cyan.withValues(alpha: .35)
          ..strokeWidth = 2,
      );
    }
    canvas.drawCircle(
      muzzle,
      world.upgrades[RaidUpgrade.pulse]! > 0 ? 6 : 3,
      Paint()..color = cyan.withValues(alpha: world.firing ? .9 : .35),
    );
    if (world.moduleCount > 0) {
      for (var i = 0; i < world.moduleCount; i++) {
        canvas.drawCircle(
          p.translate((-8 + i * 8).toDouble(), 31),
          3,
          Paint()..color = orange,
        );
      }
    }
  }

  void _drone(Canvas canvas, RaidDrone drone) {
    final p = Offset(drone.position.x, drone.position.y);
    final guardian = drone.kind == RaidDroneKind.guardian;
    final bob =
        (calmEffects ? 0.0 : math.sin(world.elapsed * 4 + drone.id) * 5) -
        (drone.jumpTime > 0 && !calmEffects
            ? math.sin(drone.jumpTime / .65 * math.pi) * 50
            : 0);
    final size = guardian
        ? 155.0
        : drone.kind == RaidDroneKind.sentry
        ? 100.0
        : 86.0;
    if (drone.arrival > 0) {
      canvas.drawCircle(
        p,
        drone.radius + 22,
        Paint()..color = const Color(0xffde91ff).withValues(alpha: .15),
      );
      canvas.drawCircle(
        p,
        drone.radius + 22,
        Paint()
          ..color = const Color(0xffde91ff)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    canvas.drawOval(
      Rect.fromCenter(center: p.translate(0, 13), width: size * .7, height: 25),
      Paint()..color = const Color(0x88050b15),
    );
    if (drone.repairTarget != null && drone.repairGlow > 0) {
      canvas.drawLine(
        p,
        Offset(drone.repairTarget!.x, drone.repairTarget!.y),
        Paint()
          ..color = const Color(0xff9bf5aa)
              .withValues(alpha: drone.repairGlow * 1.5)
          ..strokeWidth = 5,
      );
    }
    if (world.shielded(drone)) {
      canvas.drawCircle(
        p,
        drone.radius + 13,
        Paint()..color = const Color(0x2966cfff),
      );
      canvas.drawCircle(
        p,
        drone.radius + 13,
        Paint()
          ..color = const Color(0xff92caff)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    if (drone.kind == RaidDroneKind.pulsar ||
        drone.kind == RaidDroneKind.hopper) {
      operationSprite(
        canvas,
        drone.kind == RaidDroneKind.pulsar ? 0 : 1,
        p.translate(0, -10 + bob),
        135,
        rescue: true,
        opacity: drone.arrival > 0
            ? .4
            : drone.flash > 0
            ? .7
            : 1,
      );
    } else if (drone.kind == RaidDroneKind.bulwark ||
        drone.kind == RaidDroneKind.boomerang) {
      final exposed =
          drone.kind == RaidDroneKind.bulwark && !world.shielded(drone);
      canvas.saveLayer(
        Rect.fromCenter(center: p, width: 150, height: 150),
        Paint()
          ..colorFilter = exposed
              ? const ColorFilter.matrix([
                  .3,
                  .59,
                  .11,
                  0,
                  0,
                  .3,
                  .59,
                  .11,
                  0,
                  0,
                  .3,
                  .59,
                  .11,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ])
              : null,
      );
      operationSprite(
        canvas,
        drone.kind == RaidDroneKind.bulwark ? 0 : 1,
        p.translate(0, -10 + bob),
        110,
        portal: true,
        opacity: drone.arrival > 0
            ? .4
            : drone.flash > 0
            ? .7
            : 1,
      );
      canvas.restore();
      if (exposed) {
        canvas.drawCircle(
          p,
          drone.radius + 13,
          Paint()
            ..color = const Color(0xffffc270)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    } else if (drone.kind == RaidDroneKind.prism ||
        drone.kind == RaidDroneKind.bomber) {
      operationSprite(
        canvas,
        drone.kind == RaidDroneKind.bomber ? 1 : 2,
        p.translate(0, -10 + bob),
        132,
        opacity: drone.arrival > 0
            ? .4
            : drone.flash > 0
            ? .7
            : 1,
      );
    } else if ({
      RaidDroneKind.interceptor,
      RaidDroneKind.repairer,
      RaidDroneKind.relay,
    }.contains(drone.kind)) {
      _specialDrone(canvas, drone, p.translate(0, -8 + bob));
    } else {
      sprite(
        canvas,
        guardian ? 2 : 1,
        p.translate(0, -16 + bob),
        Size.square(size),
        opacity: drone.arrival > 0
            ? .4
            : drone.flash > 0
            ? .7
            : 1,
      );
    }
    final bar = Rect.fromLTWH(
      p.dx - size * .3,
      p.dy - size * .51 + bob,
      size * .6,
      guardian ? 7 : 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(4)),
      Paint()..color = const Color(0xff172435),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bar.left,
          bar.top,
          bar.width * (drone.hp / drone.maxHp).clamp(0, 1),
          bar.height,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = guardian ? orange : const Color(0xffff9394),
    );
  }

  void _specialDrone(Canvas canvas, RaidDrone drone, Offset p) {
    canvas.save();
    canvas.translate(p.dx, p.dy);
    final color = switch (drone.kind) {
      RaidDroneKind.interceptor => const Color(0xffffb566),
      RaidDroneKind.repairer => const Color(0xff8decab),
      _ => const Color(0xffc5a3ff),
    };
    final shell = Path();
    if (drone.kind == RaidDroneKind.interceptor) {
      canvas.rotate(math.atan2(drone.aim.y, drone.aim.x) + math.pi / 2);
      shell
        ..moveTo(0, -35)
        ..lineTo(31, 24)
        ..lineTo(11, 16)
        ..lineTo(0, 29)
        ..lineTo(-11, 16)
        ..lineTo(-31, 24)
        ..close();
      if (drone.chargeTime > 0) {
        canvas.drawLine(
          const Offset(0, 23),
          const Offset(0, 65),
          Paint()
            ..color = color.withValues(alpha: .7)
            ..strokeWidth = 13
            ..strokeCap = StrokeCap.round,
        );
      }
    } else if (drone.kind == RaidDroneKind.repairer) {
      shell.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-28, -25, 56, 50),
          const Radius.circular(15),
        ),
      );
      for (final x in [-39.0, 39.0]) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, 0), width: 21, height: 40),
          Paint()..color = color,
        );
      }
    } else {
      for (var i = 0; i < 6; i++) {
        final angle = i * math.pi / 3 - math.pi / 2;
        final point = Offset(math.cos(angle) * 32, math.sin(angle) * 32);
        if (i == 0) {
          shell.moveTo(point.dx, point.dy);
        } else {
          shell.lineTo(point.dx, point.dy);
        }
      }
      shell.close();
      canvas.drawCircle(
        Offset.zero,
        43,
        Paint()
          ..color = color.withValues(alpha: .65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    canvas.drawPath(shell, Paint()..color = const Color(0xff142f43));
    canvas.drawPath(
      shell,
      Paint()
        ..color = color.withValues(alpha: drone.arrival > 0 ? .45 : 1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = drone.flash > 0 ? 7 : 4,
    );
    if (drone.kind == RaidDroneKind.repairer) {
      canvas.drawLine(
        const Offset(-12, 0),
        const Offset(12, 0),
        Paint()
          ..color = color
          ..strokeWidth = 8,
      );
      canvas.drawLine(
        const Offset(0, -12),
        const Offset(0, 12),
        Paint()
          ..color = color
          ..strokeWidth = 8,
      );
    } else {
      canvas.drawCircle(
        Offset.zero,
        drone.kind == RaidDroneKind.relay ? 13 : 9,
        Paint()..color = color,
      );
      canvas.drawCircle(const Offset(-3, -3), 3, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  void _beacon(Canvas canvas) {
    final p = Offset(raidBeacon.x, raidBeacon.y);
    final enabled = world.canLaunch || world.phase == RaidPhase.won;
    canvas.drawCircle(
      p,
      80,
      Paint()..color = cyan.withValues(alpha: enabled ? .21 : .07),
    );
    canvas.drawCircle(
      p,
      80,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = enabled ? cyan : const Color(0xff58788a),
    );
    if (world.phase == RaidPhase.won) {
      canvas.drawRect(
        Rect.fromLTWH(p.dx - 17, 0, 34, p.dy),
        Paint()..color = cyan.withValues(alpha: .55),
      );
      canvas.drawRect(
        Rect.fromLTWH(p.dx - 45, 0, 90, p.dy),
        Paint()..color = cyan.withValues(alpha: .13),
      );
    }
    sprite(
      canvas,
      5,
      p.translate(0, -25),
      const Size(175, 175),
      opacity: enabled ? 1 : .7,
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        p.translate((i - 1) * 30, 64),
        7,
        Paint()..color = i < world.coreCount ? cyan : const Color(0xff3e576a),
      );
    }
  }

  RaidVec get _target {
    if (world.escorting &&
        !world.convoyAtStop &&
        (world.coreUnlocked || world.coreCount == 3 && !world.guardianAlive)) {
      return world.convoy.position;
    }
    final relay = world.drones
        .where((d) => d.kind == RaidDroneKind.relay && d.hp > 0)
        .firstOrNull;
    if (relay != null) return relay.position;
    if (world.coreCount == 3) {
      return world.drones
              .where((d) => d.kind == RaidDroneKind.guardian)
              .firstOrNull
              ?.position ??
          raidBeacon;
    }
    if (!world.coreUnlocked && world.drones.isNotEmpty) {
      final pending = world.drones.toList()
        ..sort(
          (a, b) => a.position
              .distance(world.player)
              .compareTo(b.position.distance(world.player)),
        );
      return pending.first.position;
    }
    if (!world.portalReady) return raidPortals[world.coreCount].entry;
    if (!world.rescueReady && world.carriedRescue == null) {
      return raidRescueBots[world.coreCount];
    }
    return raidCores[world.coreCount];
  }

  void _rescuePads(Canvas canvas) {
    if (world.mission != RaidMission.rescue) return;
    for (var i = 0; i < 3; i++) {
      final p = Offset(raidCores[i].x, raidCores[i].y);
      final current = i == world.coreCount;
      canvas.drawCircle(
        p,
        65,
        Paint()..color = cyan.withValues(alpha: current ? .12 : .04),
      );
      canvas.drawCircle(
        p,
        65,
        Paint()
          ..color = cyan.withValues(alpha: current ? .8 : .25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      if (current && world.carriedRescue != null) {
        final bot = Offset(world.player.x, world.player.y);
        canvas.drawLine(
          bot,
          p,
          Paint()
            ..color = cyan.withValues(alpha: .3)
            ..strokeWidth = 3,
        );
      }
    }
  }

  void _rescueRobot(Canvas canvas, int i) {
    final at = world.rescuePosition(i), p = Offset(at.x, at.y);
    final opacity = i <= world.coreCount ? 1.0 : .3;
    canvas.drawCircle(
      p,
      world.carriedRescue == i ? 22 : 32,
      Paint()
        ..color =
            (world.rescuedBots.contains(i) ? const Color(0xff9bf5aa) : cyan)
                .withValues(alpha: .15 * opacity),
    );
    operationSprite(
      canvas,
      2,
      p,
      world.carriedRescue == i ? 75 : 95,
      rescue: true,
      opacity: opacity,
    );
    if (world.rescuedBots.contains(i)) {
      canvas.drawPath(
        Path()
          ..moveTo(p.dx - 10, p.dy - 38)
          ..lineTo(p.dx - 3, p.dy - 31)
          ..lineTo(p.dx + 12, p.dy - 46),
        Paint()
          ..color = const Color(0xff9bf5aa)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }
  }

  void _orbitGuard(Canvas canvas) {
    final at = world.orbitPosition, p = Offset(at.x, at.y);
    final ready = world.orbitCooldown == 0;
    operationSprite(canvas, 2, p, 65, rescue: true, opacity: ready ? 1 : .4);
    canvas.drawCircle(
      p,
      25,
      Paint()
        ..color = cyan.withValues(alpha: ready ? .8 : .25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final recharge = world.upgrades[RaidUpgrade.orbit] == 2 ? 1.8 : 3;
    canvas.drawArc(
      Rect.fromCircle(center: p, radius: 29),
      -math.pi / 2,
      (1 - world.orbitCooldown / recharge).clamp(0, 1) * math.pi * 2,
      false,
      Paint()
        ..color = orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _meteorField(Canvas canvas) {
    for (final meteor in world.meteors) {
      final p = Offset(meteor.position.x, meteor.position.y);
      final warning = meteor.delay > 0;
      canvas.drawCircle(
        p,
        RaidMeteor.radius,
        Paint()..color = orange.withValues(alpha: warning ? .12 : .3),
      );
      canvas.drawCircle(
        p,
        RaidMeteor.radius,
        Paint()
          ..color = orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      if (warning) {
        canvas.drawArc(
          Rect.fromCircle(center: p, radius: RaidMeteor.radius - 8),
          -math.pi / 2,
          (1 - meteor.delay / 1.3).clamp(0, 1) * math.pi * 2,
          false,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5,
        );
        canvas.drawLine(
          p.translate(-15, 0),
          p.translate(15, 0),
          Paint()
            ..color = orange
            ..strokeWidth = 4,
        );
        canvas.drawLine(
          p.translate(0, -15),
          p.translate(0, 15),
          Paint()
            ..color = orange
            ..strokeWidth = 4,
        );
        if (!calmEffects && meteor.delay < .35) {
          operationSprite(
            canvas,
            3,
            p.translate(0, -meteor.delay * 500),
            135,
            rescue: true,
            opacity: .85,
          );
        }
      } else {
        operationSprite(
          canvas,
          3,
          p,
          150,
          rescue: true,
          opacity: (meteor.life / .4).clamp(0, 1),
        );
      }
    }
  }

  void _transport(Canvas canvas) {
    for (final belt in world.conveyors) {
      final area = belt.area;
      final rect = Rect.fromLTWH(area.x, area.y, area.width, area.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(16)),
        Paint()..color = const Color(0x553cddf5),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(16)),
        Paint()
          ..color = cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      final length = math.max(area.width, area.height);
      final flow = area.width > area.height
          ? belt.direction.x
          : belt.direction.y;
      final shift = calmEffects || !world.simulating
          ? 0.0
          : world.elapsed * 40 * flow % 65;
      for (var at = shift - 65; at < length + 65; at += 65) {
        if (at < 25 || at > length - 25) continue;
        final p = area.width > area.height
            ? Offset(area.x + at, area.y + area.height / 2)
            : Offset(area.x + area.width / 2, area.y + at);
        final direction = Offset(belt.direction.x, belt.direction.y),
            side = Offset(-direction.dy, direction.dx);
        canvas.drawPath(
          Path()
            ..moveTo(
              (p - direction * 13 + side * 13).dx,
              (p - direction * 13 + side * 13).dy,
            )
            ..lineTo((p + direction * 6).dx, (p + direction * 6).dy)
            ..lineTo(
              (p - direction * 13 - side * 13).dx,
              (p - direction * 13 - side * 13).dy,
            ),
          Paint()
            ..color = cyan.withValues(alpha: .8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5,
        );
      }
      operationSprite(
        canvas,
        3,
        Offset(area.x + 20, area.y + 5),
        88,
        portal: true,
      );
    }
    if (world.mission != RaidMission.portal) return;
    for (var i = 0; i < raidPortals.length; i++) {
      final portal = raidPortals[i];
      final used = world.portalsUsed.contains(i);
      final active = i == world.coreCount && !used;
      final opacity = active
          ? 1.0
          : used
          ? .45
          : .25;
      for (final point in [portal.entry, portal.exit]) {
        operationSprite(
          canvas,
          2,
          Offset(point.x, point.y),
          130,
          opacity: opacity,
          portal: true,
        );
      }
      if (active) {
        final a = Offset(portal.entry.x, portal.entry.y),
            b = Offset(portal.exit.x, portal.exit.y);
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = cyan.withValues(alpha: .18)
            ..strokeWidth = 3,
        );
        canvas.drawCircle(
          a,
          49,
          Paint()
            ..color = cyan
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
        final direction = (b - a) / (b - a).distance;
        canvas.drawLine(
          b - direction * 45,
          b,
          Paint()
            ..color = cyan
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _miniMap(Canvas canvas, Size size) {
    final width = size.width < 360 ? 55.0 : 64.0;
    final rect = Rect.fromLTWH(
      size.width - width - 12,
      91,
      width,
      width * raidWorldHeight / raidWorldWidth,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(9)),
      Paint()..color = const Color(0xcc09162a),
    );
    Offset point(RaidVec p) => Offset(
      rect.left + p.x / raidWorldWidth * rect.width,
      rect.top + p.y / raidWorldHeight * rect.height,
    );
    for (final block in world.blocks) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + block.x / raidWorldWidth * rect.width,
          rect.top + block.y / raidWorldHeight * rect.height,
          block.width / raidWorldWidth * rect.width,
          block.height / raidWorldHeight * rect.height,
        ),
        Paint()..color = const Color(0xff3b5268),
      );
    }
    for (final hazard in world.hazards) {
      canvas.drawCircle(
        point(hazard.position),
        3,
        Paint()
          ..color = world.hazardCooled(hazard)
              ? cyan
              : world.hazardActive(hazard)
              ? orange
              : const Color(0xff87664a),
      );
    }
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        point(raidCores[i]),
        2.5,
        Paint()
          ..color = world.collected.contains(i)
              ? const Color(0xff476478)
              : orange,
      );
    }
    canvas.drawCircle(point(raidBeacon), 3, Paint()..color = cyan);
    if (world.mission == RaidMission.rescue) {
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          point(world.rescuePosition(i)),
          3,
          Paint()
            ..color = world.rescuedBots.contains(i)
                ? const Color(0xff9bf5aa)
                : cyan,
        );
      }
    }
    for (final drone in world.drones) {
      canvas.drawCircle(
        point(drone.position),
        2.5,
        Paint()
          ..color = drone.kind == RaidDroneKind.relay
              ? const Color(0xffc5a3ff)
              : const Color(0xffff9394),
      );
    }
    canvas.drawCircle(point(world.player), 3.5, Paint()..color = Colors.white);
    if (world.escorting) {
      canvas.drawRect(
        Rect.fromCenter(
          center: point(world.convoy.position),
          width: 6,
          height: 6,
        ),
        Paint()..color = cyan,
      );
    }
  }

  void _direction(Canvas canvas, Size size, RaidCamera camera) {
    if (world.phase != RaidPhase.playing) return;
    final target = camera.point(_target);
    final bounds = Rect.fromLTRB(
      55,
      98,
      size.width - 55,
      math.max(125, size.height - 157),
    );
    if (bounds.contains(target)) return;
    final player = camera.point(world.player);
    final direction = target - player;
    if (direction.distance < 1) return;
    final t = math.min(
      direction.dx.abs() < 1
          ? double.infinity
          : (bounds.width / 2) / direction.dx.abs(),
      direction.dy.abs() < 1
          ? double.infinity
          : (bounds.height / 2) / direction.dy.abs(),
    );
    final center = bounds.center + direction * t;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.atan2(direction.dy, direction.dx));
    canvas.drawCircle(
      Offset.zero,
      16,
      Paint()..color = const Color(0xdd0c1c30),
    );
    canvas.drawPath(
      Path()
        ..moveTo(7, 0)
        ..lineTo(-5, -6)
        ..lineTo(-5, 6)
        ..close(),
      Paint()..color = orange,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RayRaidPainter oldDelegate) =>
      !identical(world, oldDelegate.world) ||
      !identical(art, oldDelegate.art) ||
      calmEffects != oldDelegate.calmEffects;
}
