import 'dart:collection';
import 'dart:math' as math;

import 'package:mykids_family/engagement/ray_raid_model.dart';

/// Read-only planning. Native QA translates the result into ordinary gestures.
class RaidPilot {
  RaidVec goal(RayRaidWorld w) {
    if (w.escorting &&
        !w.convoyAtStop &&
        (w.coreUnlocked || w.coreCount == 3 && !w.guardianAlive)) {
      if (w.player.distance(w.convoy.position) > 170) return w.convoy.position;
      final toward = w.convoyNextPoint - w.convoy.position;
      return w.convoy.position + toward.unit * math.min(120, toward.length);
    }
    if (w.coreCount < 3 && w.coreUnlocked) {
      if (!w.portalReady) return raidPortals[w.coreCount].entry;
      if (!w.rescueReady && w.carriedRescue == null) {
        return raidRescueBots[w.coreCount];
      }
      return raidCores[Iterable<int>.generate(3)
          .firstWhere((i) => !w.collected.contains(i))];
    }
    final candidates =
        w.drones.where((d) => d.hp > 0 && !w.shielded(d)).toList()..sort(
          (a, b) => a.position
              .distance(w.player)
              .compareTo(b.position.distance(w.player)),
        );
    final boss =
        candidates.firstOrNull ?? w.drones.where((d) => d.hp > 0).firstOrNull;
    if (boss == null) return raidBeacon;
    if (w.lineBlocked(w.player, boss.position, 28)) return boss.position;
    final angle =
        math.atan2(w.player.y - boss.position.y, w.player.x - boss.position.x) +
        .6;
    for (final turn in [0.0, -1.2, .6, -1.8, 1.2, -2.4, 1.8]) {
      final point = clampToArena(
        boss.position +
            RaidVec(math.cos(angle + turn), math.sin(angle + turn)) *
                (w.upgrades[RaidUpgrade.shock]! > 0 ? 150 : 240),
        30,
      );
      if (!w.blocks.any((b) => b.contains(point, 28)) &&
          !w.lineBlocked(point, boss.position)) {
        return point;
      }
    }
    return boss.position;
  }

  RaidVec movement(RayRaidWorld w) {
    RaidVec? escape(RaidVec point, double radius) {
      if (w.player.distance(point) >= radius) return null;
      final away = (w.player - point).unit;
      final base = away.length > .1 ? away : const RaidVec(1, 0);
      for (final angle in [0.0, .6, -.6, 1.2, -1.2, 1.8, -1.8, math.pi]) {
        final direction = base.rotated(angle);
        final target = w.player + direction * 110;
        if (!w.lineBlocked(w.player, target, 22) &&
            clampToArena(target, 22).distance(target) < 1 &&
            target.distance(point) > w.player.distance(point) + 20) {
          return direction;
        }
      }
      return null;
    }

    for (final meteor in w.meteors) {
      final direction = escape(meteor.position, RaidMeteor.radius + 60);
      if (direction != null) return direction;
    }
    for (final d in w.drones) {
      if (d.kind == RaidDroneKind.hopper && (d.windup > 0 || d.jumpTime > 0)) {
        final direction = escape(d.jumpTarget, RaidBlast.radius + 60);
        if (direction != null) return direction;
      }
      if (d.kind == RaidDroneKind.pulsar && d.windup > 0) {
        final direction = escape(d.position, RaidPulseRing.limit + 45);
        if (direction != null) return direction;
      }
    }
    for (final ring in w.pulseRings) {
      if (w.player.distance(ring.position) > ring.radius - 30) {
        final direction = escape(ring.position, RaidPulseRing.limit + 40);
        if (direction != null) return direction;
      }
    }
    if (w.upgrades[RaidUpgrade.orbit]! > 0 &&
        w.orbitBlocks == 0 &&
        w.orbitCooldown == 0 &&
        w.bolts.any((b) => _incoming(w, b, 180))) {
      return RaidVec.zero;
    }
    final blast = w.blasts
        .where((b) => w.player.distance(b.position) < RaidBlast.radius + 55)
        .firstOrNull;
    if (blast != null) {
      final away = (w.player - blast.position).unit;
      final direction = away.length > .1 ? away : const RaidVec(1, 0);
      if (!w.lineBlocked(w.player, w.player + direction * 120, 27)) {
        return direction;
      }
    }
    for (final d in w.drones.where(
      (d) => d.kind == RaidDroneKind.prism && d.windup > 0,
    )) {
      final end = w.rayEnd(d.position, d.aim);
      if (segmentDistance(w.player, d.position, end) < 65) {
        final side = RaidVec(-d.aim.y, d.aim.x);
        for (final sign in [1.0, -1.0]) {
          final direction = side * sign;
          if (!w.lineBlocked(w.player, w.player + direction * 120, 27)) {
            return direction;
          }
        }
      }
    }
    final nearby = w.hazards
        .where(
          (h) =>
              (w.hazardActive(h) || w.hazardWarning(h)) &&
              w.player.distance(h.position) < h.radius + 55,
        )
        .firstOrNull;
    if (nearby != null) {
      final away = (w.player - nearby.position).unit;
      final target =
          w.player + (away.length > .1 ? away : const RaidVec(1, 0)) * 130;
      if (!w.lineBlocked(w.player, target, 27)) return (target - w.player).unit;
    }
    final close = w.drones
        .where(
          (d) =>
              d.hp > 0 &&
              d.arrival == 0 &&
              w.player.distance(d.position) < d.radius + 75,
        )
        .firstOrNull;
    if (close != null) {
      final away = (w.player - close.position).unit;
      for (final angle in [0.0, .6, -.6, 1.2, -1.2, 1.8, -1.8]) {
        final direction = away.rotated(angle);
        final target = w.player + direction * 100;
        if (!w.lineBlocked(w.player, target, 22) &&
            clampToArena(target, 22).distance(target) < 1) {
          return direction;
        }
      }
    }
    return toward(w.player, goal(w), blocks: w.blocks);
  }

  bool _incoming(
    RayRaidWorld w,
    RaidBolt bolt,
    double range, {
    RaidVec? target,
    RaidVec? targetVelocity,
  }) {
    final at = target ?? w.player;
    if (!bolt.hostile || bolt.position.distance(at) > range) return false;
    final velocity =
        bolt.velocity * w.enemyTimeScale(bolt.position) -
        (targetVelocity ?? w.movement * w.movementSpeed);
    final toward = at - bolt.position;
    if (toward.x * velocity.x + toward.y * velocity.y <= 0) return false;
    return segmentDistance(at, bolt.position, bolt.position + velocity * .75) <
        48;
  }

  bool danger(RayRaidWorld w) =>
      (w.escorting &&
          w.player.distance(w.convoy.position) <= 210 &&
          (w.bolts.any(
                (b) => _incoming(
                  w,
                  b,
                  190,
                  target: w.convoy.position,
                  targetVelocity: w.convoyAtStop
                      ? RaidVec.zero
                      : (w.convoyNextPoint - w.convoy.position).unit * 115,
                ),
              ) ||
              w.blasts.any(
                (b) =>
                    b.position.distance(w.convoy.position) <
                    RaidBlast.radius + 45,
              ) ||
              w.drones.any(
                (d) =>
                    d.kind == RaidDroneKind.prism &&
                    d.windup > 0 &&
                    segmentDistance(
                          w.convoy.position,
                          d.position,
                          w.rayEnd(d.position, d.aim),
                        ) <
                        65,
              ))) ||
      w.meteors.any(
        (m) =>
            m.delay < .5 &&
            m.position.distance(w.player) < RaidMeteor.radius + 45,
      ) ||
      w.pulseRings.any(
        (r) => (r.position.distance(w.player) - r.radius).abs() < 65,
      ) ||
      w.drones.any(
        (d) =>
            d.kind == RaidDroneKind.hopper &&
            (d.windup > 0 || d.jumpTime > 0) &&
            d.jumpTarget.distance(w.player) < RaidBlast.radius + 45,
      ) ||
      w.bolts.any((b) => _incoming(w, b, 160)) ||
      w.drones.any(
        (d) => d.chargeTime > 0 && d.position.distance(w.player) < 200,
      ) ||
      w.drones.any(
        (d) =>
            d.hp > 0 &&
            d.arrival == 0 &&
            w.player.distance(d.position) < d.radius + 70,
      ) ||
      w.hazards.any(
        (h) =>
            w.hazardActive(h) && h.position.distance(w.player) < h.radius + 35,
      ) ||
      w.blasts.any(
        (b) => b.position.distance(w.player) < RaidBlast.radius + 55,
      ) ||
      w.drones.any(
        (d) =>
            d.kind == RaidDroneKind.prism &&
            d.windup > 0 &&
            segmentDistance(w.player, d.position, w.rayEnd(d.position, d.aim)) <
                70,
      );

  bool shouldDash(RayRaidWorld w) =>
      w.movement.length > .1 &&
      w.dashCooldown == 0 &&
      !w.lineBlocked(w.player, w.player + w.movement.unit * 190, 25) &&
      (w.upgrades[RaidUpgrade.shock]! > 0 &&
              w.drones.any(
                (d) =>
                    d.hp > 0 &&
                    d.arrival == 0 &&
                    !w.shielded(d) &&
                    w.player.distance(d.position) < 160,
              ) ||
          w.bolts.any((b) => _incoming(w, b, 95)) ||
          w.meteors.any(
            (m) =>
                m.delay < .4 &&
                m.position.distance(w.player) < RaidMeteor.radius + 45,
          ) ||
          w.pulseRings.any(
            (r) => (r.position.distance(w.player) - r.radius).abs() < 65,
          ) ||
          w.drones.any(
            (d) =>
                d.kind == RaidDroneKind.hopper &&
                d.jumpTime > 0 &&
                d.jumpTime < .3 &&
                d.jumpTarget.distance(w.player) < RaidBlast.radius + 45,
          ) ||
          w.blasts.any(
            (b) =>
                b.delay < .3 &&
                b.position.distance(w.player) < RaidBlast.radius + 30,
          ) ||
          w.drones.any(
            (d) =>
                d.kind == RaidDroneKind.prism &&
                d.windup > 0 &&
                d.windup < .3 &&
                segmentDistance(
                      w.player,
                      d.position,
                      w.rayEnd(d.position, d.aim),
                    ) <
                    45,
          ));

  RaidVec fireAim(RayRaidWorld w) {
    // Deliberately try the newly selected module through an ordinary aimed shot.
    if (w.upgrades[RaidUpgrade.ricochet]! > 0 && w.ricochetBounces == 0) {
      final blocks = w.blocks.toList()
        ..sort(
          (a, b) => a.center
              .distance(w.player)
              .compareTo(b.center.distance(w.player)),
        );
      return (blocks.first.center - w.player).unit;
    }
    return RaidVec.zero;
  }

  RaidVec toward(
    RaidVec player,
    RaidVec target, {
    List<RaidBlock> blocks = raidBlocks,
  }) {
    if (player.distance(target) < 18) return RaidVec.zero;
    if (!segmentHitsCover(player, target, 27, blocks)) {
      return (target - player).unit;
    }
    const step = 40.0, cols = 28, rows = 37;
    (int, int) cell(RaidVec p) => (
      (p.x / step).floor().clamp(0, cols - 1),
      (p.y / step).floor().clamp(0, rows - 1),
    );
    RaidVec point((int, int) c) => RaidVec(c.$1 * step + 20, c.$2 * step + 20);
    bool open((int, int) c) {
      final p = point(c);
      return c.$1 >= 0 &&
          c.$1 < cols &&
          c.$2 >= 0 &&
          c.$2 < rows &&
          p.x > 60 &&
          p.x < raidWorldWidth - 60 &&
          p.y > 60 &&
          p.y < raidWorldHeight - 60 &&
          !blocks.any((b) => b.contains(p, 27));
    }

    final start = cell(player), wanted = cell(target);
    final queue = Queue<(int, int)>()..add(start);
    final previous = <(int, int), (int, int)?>{start: null};
    (int, int)? found;
    while (queue.isNotEmpty) {
      final c = queue.removeFirst();
      if (c == wanted ||
          point(c).distance(target) < 50 &&
              !segmentHitsCover(point(c), target, 27, blocks)) {
        found = c;
        break;
      }
      for (final d in const [
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (1, 1),
        (-1, -1),
        (1, -1),
        (-1, 1),
      ]) {
        final next = (c.$1 + d.$1, c.$2 + d.$2);
        if (!previous.containsKey(next) &&
            open(next) &&
            !segmentHitsCover(
              c == start ? player : point(c),
              point(next),
              c == start ? 22 : 27,
              blocks,
            )) {
          previous[next] = c;
          queue.add(next);
        }
      }
    }
    if (found == null) return (target - player).unit;
    while (previous[found] != null && previous[found] != start) {
      found = previous[found]!;
    }
    return (point(found!) - player).unit;
  }
}
