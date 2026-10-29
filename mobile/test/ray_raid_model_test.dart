import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:mykids_family/engagement/ray_raid_model.dart';

import 'support/ray_raid_pilot.dart';

void main() {
  void run(RayRaidWorld w, double seconds) {
    for (var i = 0; i < (seconds * 120).ceil(); i++) {
      w.advance(1 / 120);
    }
  }

  RayRaidWorld started() => RayRaidWorld()..start();
  void clearSector(RayRaidWorld w) {
    for (var wave = 0; wave < 2 && !w.coreUnlocked; wave++) {
      for (final d in w.drones) {
        d.hp = 0;
      }
      run(w, .02);
    }
    expect(w.coreUnlocked, true);
  }

  void incoming(RayRaidWorld w) => w.bolts.add(
    RaidBolt(w.player + const RaidVec(-70, 0), const RaidVec(700, 0), true, 1),
  );

  test(
    'layout gives each core/start/beacon a reachable collision-free area',
    () {
      for (final p in [raidStart, raidBeacon, ...raidCores]) {
        expect(raidBlocks.any((b) => b.contains(p, 24)), false);
      }
      expect(raidCores, hasLength(3));
      final w = started();
      w.start();
      expect(w.drones, hasLength(2));
    },
  );
  test(
    'invalid inputs and long frame gaps cannot teleport or fast-forward',
    () {
      final w = started();
      w.setMove(const RaidVec(double.nan, double.infinity));
      w.advance(double.nan);
      expect(w.player.distance(raidStart), 0);
      w.setMove(const RaidVec(100, 0));
      w.advance(300);
      expect(w.player.distance(raidStart), lessThanOrEqualTo(22));
      expect(w.elapsed, lessThanOrEqualTo(.101));
      expect(w.player.finite, true);
    },
  );
  test('diagonal and straight movement have the same maximum speed', () {
    final a = started()..setMove(const RaidVec(1, 0));
    final b = started()..setMove(const RaidVec(1, -1));
    run(a, .1);
    run(b, .1);
    expect(
      a.player.distance(raidStart),
      closeTo(b.player.distance(raidStart), .001),
    );
  });
  test(
    'dash stops at crates and arena boundaries, never crossing solid cover',
    () {
      final w = started()..player = const RaidVec(350, 1200);
      w.setMove(const RaidVec(1, 0));
      expect(w.dash(), true);
      run(w, .25);
      expect(w.player.x, lessThanOrEqualTo(368));
      expect(raidBlocks.any((b) => b.contains(w.player, 22)), false);
      w.player = const RaidVec(60, 1350);
      w.dashCooldown = 0;
      w.setMove(const RaidVec(-1, 0));
      w.dash();
      run(w, .3);
      expect(w.player.x, greaterThanOrEqualTo(57));
    },
  );
  test('dash has a real cooldown and protects against incoming pulses', () {
    final w = started();
    w.setMove(const RaidVec(0, -1));
    expect(w.dash(), true);
    expect(w.dash(), false);
    for (var i = 0; i < 12; i++) {
      w.bolts.add(RaidBolt(w.player, RaidVec.zero, true, 1));
      run(w, 1 / 120);
    }
    expect(w.health, 6);
    w.setMove(RaidVec.zero);
    run(w, 4.1);
    expect(w.dash(), true);
  });
  test('shield absorbs two hits then exposes the ordinary hull', () {
    final w = started();
    w.drones.clear();
    expect(w.shield(), true);
    expect(w.shield(), false);
    incoming(w);
    run(w, .13);
    expect(w.health, 6);
    expect(w.shieldCharges, 1);
    run(w, .25);
    incoming(w);
    run(w, .13);
    expect(w.health, 6);
    expect(w.shieldCharges, 0);
    run(w, .25);
    incoming(w);
    run(w, .13);
    expect(w.health, 5);
  });
  test('burst hits cannot erase all health in the same frame', () {
    final w = started();
    w.drones.clear();
    for (var i = 0; i < 12; i++) {
      incoming(w);
    }
    run(w, .15);
    expect(w.health, 5);
    run(w, .9);
    incoming(w);
    run(w, .15);
    expect(w.health, 4);
  });
  test('friendly and hostile projectiles respect cover at high speed', () {
    final w = started()..player = const RaidVec(330, 1200);
    w.drones.clear();
    final drone = RaidDrone(42, RaidDroneKind.sentry, const RaidVec(600, 1200));
    w.drones.add(drone);
    w.setAim(const RaidVec(1, 0), shooting: true);
    run(w, 1.2);
    expect(drone.hp, drone.maxHp);
    expect(w.health, 6);
    expect(
      segmentHitsCover(const RaidVec(330, 1200), const RaidVec(600, 1200)),
      true,
    );
  });
  test('real pulses disable a visible drone and produce bounded feedback', () {
    final w = started();
    w.drones.clear();
    w.drones.add(RaidDrone(3, RaidDroneKind.scout, const RaidVec(560, 1100)));
    w.setAim(RaidVec.zero, shooting: true);
    run(w, 3.2);
    expect(w.disabledDrones, 1);
    expect(w.encounterWave, 1);
    expect(w.effects.any((e) => e.kind == RaidEffectKind.drone), true);
  });
  test(
    'each collected core pauses combat and grants exactly one upgrade choice',
    () {
      final w = started();
      clearSector(w);
      w.player = raidCores[0];
      run(w, .02);
      expect(w.phase, RaidPhase.upgrade);
      expect(w.coreCount, 1);
      final pos = w.player;
      run(w, 20);
      expect(w.player.distance(pos), 0);
      expect(w.selectUpgrade(RaidUpgrade.pulse), true);
      expect(w.selectUpgrade(RaidUpgrade.pulse), false);
      expect(w.moduleCount, 1);
      run(w, .1);
      expect(w.coreCount, 1);
      expect(w.accumulator, greaterThanOrEqualTo(0));
    },
  );
  test('tiers have visible mechanical effects and cannot exceed their cap', () {
    final w = started();
    for (var i = 0; i < 2; i++) {
      clearSector(w);
      w.player = raidCores[i];
      run(w, .02);
      expect(w.selectUpgrade(RaidUpgrade.pulse), true);
    }
    expect(w.shotInterval, lessThan(.32));
    clearSector(w);
    w.player = raidCores[2];
    run(w, .02);
    expect(w.selectUpgrade(RaidUpgrade.pulse), false);
    expect(w.phase, RaidPhase.upgrade);
    expect(w.selectUpgrade(RaidUpgrade.shield), true);
    expect(w.maxHealth, 7);
    expect(w.moduleCount, 3);
    expect(w.guardianAlive, true);
  });
  test('victory requires all three cores, disabled guardian and reaching the beacon', () {
    final w = started();
    w.drones.clear();
    w.player = raidBeacon;
    run(w, .1);
    expect(w.phase, RaidPhase.playing);
    for (var i = 0; i < 3; i++) {
      clearSector(w);
      w.player = raidCores[i];
      run(w, .02);
      w.selectUpgrade(RaidUpgrade.values[i]);
    }
    w.player = raidBeacon;
    run(w, .1);
    expect(w.phase, RaidPhase.playing);
    w.drones.singleWhere((d) => d.kind == RaidDroneKind.guardian).hp = 0;
    run(w, .02);
    expect(w.phase, RaidPhase.won);
    expect(w.canLaunch, true);
    expect(w.effects.last.kind, RaidEffectKind.win);
  });
  test(
    'pause clears held controls and freezes enemies, projectiles and cooldowns',
    () {
      final w = started();
      w.setMove(const RaidVec(1, 0));
      w.setAim(RaidVec.zero, shooting: true);
      w.shield();
      run(w, .1);
      w.setPaused(true);
      final pos = w.player, time = w.elapsed, cooldown = w.shieldCooldown;
      run(w, 30);
      expect(w.player.distance(pos), 0);
      expect(w.elapsed, time);
      expect(w.shieldCooldown, cooldown);
      w.setPaused(false);
      run(w, .1);
      expect(w.player.distance(pos), 0);
      expect(w.firing, false);
    },
  );
  test('zero health ends the run and prevents new actions', () {
    final w = started();
    w.drones.clear();
    w.health = 1;
    incoming(w);
    run(w, .15);
    expect(w.phase, RaidPhase.lost);
    expect(w.dash(), false);
    expect(w.shield(), false);
    final pos = w.player;
    w.setMove(const RaidVec(1, 0));
    run(w, 10);
    expect(w.player.distance(pos), 0);
  });
  test('cores require both waves in order and refill the hull, with fair drone arrivals', () {
    final w = started();
    w.player = raidCores[0];
    run(w, .02);
    expect(w.phase, RaidPhase.playing);
    expect(w.coreCount, 0);
    for (final d in w.drones) {
      d.hp = 0;
    }
    run(w, .02);
    expect(w.encounterWave, 1);
    expect(w.coreUnlocked, false);
    expect(
      w.drones.every(
        (d) =>
            d.arrival > 0 &&
            !raidBlocks.any((b) => b.contains(d.position, d.radius)),
      ),
      true,
    );
    for (final d in w.drones) {
      d.hp = 0;
    }
    w.health = 2;
    w.player = raidCores[2];
    run(w, .02);
    expect(w.coreUnlocked, true);
    expect(w.coreCount, 0);
    w.player = raidCores[0];
    run(w, .02);
    expect(w.phase, RaidPhase.upgrade);
    expect(w.health, w.maxHealth);
  });
  test('a full run can be completed with normal movement, assisted aim and abilities', () {
    final w = started(), pilot = RaidPilot();
    for (
      var frame = 0;
      frame < 120 * 240 &&
          w.phase != RaidPhase.won &&
          w.phase != RaidPhase.lost;
      frame++
    ) {
      if (w.phase == RaidPhase.upgrade) {
        w.selectUpgrade(
          [
            RaidUpgrade.pulse,
            RaidUpgrade.shield,
            RaidUpgrade.dash,
          ][w.coreCount - 1],
        );
      }
      if (frame % 12 == 0) {
        w.setMove(pilot.movement(w));
        w.setAim(RaidVec.zero, shooting: true);
        if (w.bolts.any(
          (b) => b.hostile && b.position.distance(w.player) < 120,
        )) {
          w.shield();
        }
      }
      w.advance(1 / 120);
      expect(w.bolts.length, lessThanOrEqualTo(64));
      expect(w.particles.length, lessThanOrEqualTo(96));
      expect(w.effects.length, lessThanOrEqualTo(24));
      expect(w.drones.length, lessThanOrEqualTo(7));
    }
    expect(
      w.phase,
      RaidPhase.won,
      reason:
          'pos${w.player.x},${w.player.y} cores${w.coreCount} hp${w.health} drones${w.drones.length} time${w.elapsed}',
    );
    debugPrint(
      'Raid pilot: time${w.elapsed.toStringAsFixed(1)} hp${w.health} drones${w.disabledDrones} modules${w.moduleCount}',
    );
    expect(w.moduleCount, 3);
    expect(w.disabledDrones, greaterThanOrEqualTo(1));
  });
  test('manual aim stays steady while walking between shots', () {
    final w = started();
    w.setMove(const RaidVec(1, 0));
    w.setAim(const RaidVec(0, -1), shooting: true);
    run(w, .15);
    expect(w.facing.x, 0);
    expect(w.facing.y, -1);
  });
  test('guardian locks the warned pattern even across its phase change', () {
    final w = started();
    w.collected.addAll([0, 1, 2]);
    w.guardianSpawned = true;
    final d = RaidDrone(10, RaidDroneKind.guardian, const RaidVec(560, 1100))
      ..arrival = 0
      ..cooldown = 0
      ..attack = 1;
    w.drones
      ..clear()
      ..add(d);
    run(w, .02);
    expect(d.windup, greaterThan(0));
    final warned = d.shotAngles;
    d.hp = 49;
    run(w, .1);
    expect(d.shotAngles, warned);
    expect(d.shotAngles, hasLength(5));
    run(w, .9);
    expect(d.attack, 2);
    d.attack = 1;
    d.cooldown = 0;
    run(w, .02);
    expect(d.shotAngles, hasLength(12));
  });
  test('a core clears hostile pulses and gives a safe upgrade return', () {
    final w = started();
    clearSector(w);
    w.bolts.add(RaidBolt(const RaidVec(900, 1400), RaidVec.zero, true, 1));
    w.player = raidCores[0];
    run(w, .02);
    expect(w.phase, RaidPhase.upgrade);
    expect(w.bolts.where((b) => b.hostile), isEmpty);
    expect(w.immunity, greaterThan(.7));
    w.selectUpgrade(RaidUpgrade.pulse);
    run(w, .2);
    expect(w.health, w.maxHealth);
  });
}
