import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/engagement/ray_raid_model.dart';

void main() {
  void run(RayRaidWorld w, double seconds) {
    for (var i = 0; i < (seconds * 120).ceil(); i++) {
      w.advance(1 / 120);
    }
  }

  RayRaidWorld empty([RaidMission mission = RaidMission.beacon]) =>
      RayRaidWorld(mission: mission)
        ..start()
        ..drones.clear()
        ..coreUnlocked = true;
  RaidDrone still(
    int id,
    RaidVec at, [
    RaidDroneKind kind = RaidDroneKind.guardian,
  ]) => RaidDrone(id, kind, at)
    ..arrival = 0
    ..windup = 100;

  test('portal endpoints and approach paths have player clearance', () {
    final w = RayRaidWorld(mission: RaidMission.portal);
    for (final p in raidPortals) {
      for (final point in [p.entry, p.exit]) {
        expect(w.blocks.any((b) => b.contains(point, 32)), false);
        expect(clampToArena(point, 32).distance(point), 0);
      }
    }
  });

  test(
    'energy requires the current portal and each pad only transports once',
    () {
      final w = empty(RaidMission.portal)..player = raidCores[0];
      run(w, .02);
      expect(w.coreCount, 0);
      expect(w.objective, contains('портал'));
      w.player = raidPortals[0].exit;
      run(w, .02);
      expect(w.portalHops, 0, reason: 'Exit is not an entry');
      w.player = raidPortals[1].entry;
      run(w, .02);
      expect(w.portalHops, 0, reason: 'Future sector stays inactive');
      w.player = raidPortals[0].entry;
      run(w, .02);
      expect(w.player.distance(raidPortals[0].exit), 0);
      expect(w.immunity, greaterThan(.6));
      expect(w.portalsUsed, {0});
      w.player = raidPortals[0].entry;
      run(w, .1);
      expect(w.player.distance(raidPortals[0].entry), 0);
      expect(w.portalHops, 1);
      w.player = raidCores[0];
      run(w, .02);
      expect(w.phase, RaidPhase.upgrade);
      expect(w.coreCount, 1);
      expect(w.portalReady, false);
    },
  );

  test('a portal cannot skip either combat wave or run while paused', () {
    final w = RayRaidWorld(mission: RaidMission.portal)..start();
    w.player = raidPortals[0].entry;
    w.setPaused(true);
    run(w, 2);
    expect(w.portalHops, 0);
    w.setPaused(false);
    run(w, .02);
    expect(w.portalHops, 1);
    w.player = raidCores[0];
    run(w, .02);
    expect(w.coreCount, 0);
    w.drones.clear();
    run(w, .02);
    expect(w.encounterWave, 1);
    expect(w.coreCount, 0);
  });

  test(
    'conveyors push by arrows, remain controllable and stop at the arena edge',
    () {
      final w = empty(RaidMission.magnet)..player = const RaidVec(300, 1320);
      run(w, 1);
      expect(w.player.x, closeTo(215, 1));
      expect(w.conveyorSteps, 120);
      w.setMove(const RaidVec(1, 0));
      run(w, .5);
      expect(w.player.x, greaterThan(275));
      w.clearInput();
      w.player = const RaidVec(140, 1320);
      w.setMove(const RaidVec(-1, 0));
      run(w, 3);
      expect(w.player.x, 57);
      expect(w.blocks.any((b) => b.contains(w.player, 21.9)), false);
    },
  );

  test('conveyors freeze during pause and upgrade selection', () {
    final w = empty(RaidMission.magnet)..player = const RaidVec(300, 1320);
    w.setPaused(true);
    run(w, 3);
    expect(w.player.x, 300);
    w.setPaused(false);
    w.phase = RaidPhase.upgrade;
    run(w, 3);
    expect(w.player.x, 300);
    expect(w.conveyorSteps, 0);
  });

  test(
    'bulwark shield has a bounded vulnerable window and pauses with the world',
    () {
      final w = empty();
      final d = still(100, const RaidVec(700, 1320), RaidDroneKind.bulwark);
      w.drones.add(d);
      expect(w.shielded(d), true);
      w.bolts.add(
        RaidBolt(const RaidVec(650, 1320), const RaidVec(620, 0), false, 1),
      );
      run(w, .1);
      expect(d.hp, d.maxHp);
      run(w, 1.5);
      expect(w.shielded(d), false);
      w.bolts.add(
        RaidBolt(const RaidVec(650, 1320), const RaidVec(620, 0), false, 1),
      );
      run(w, .1);
      expect(d.hp, d.maxHp - 1);
      final clock = d.guardClock;
      w.setPaused(true);
      run(w, 10);
      expect(d.guardClock, clock);
      w.setPaused(false);
      run(w, 2.4);
      expect(w.shielded(d), true);
    },
  );

  test(
    'boomerang warns before firing and reverses once toward its launch point',
    () {
      final w = empty()..player = const RaidVec(560, 1400);
      final d = still(100, const RaidVec(560, 1100), RaidDroneKind.boomerang)
        ..windup = 0
        ..cooldown = 0;
      w.drones.add(d);
      run(w, .02);
      expect(d.windup, greaterThan(.6));
      expect(w.returnAttacks, 0);
      run(w, .65);
      expect(w.returnAttacks, 1);
      final bolt = w.bolts.single;
      expect(bolt.velocity.y, greaterThan(0));
      w.player = const RaidVec(850, 1400);
      run(w, .85);
      expect(bolt.returned, true);
      expect(bolt.velocity.y, lessThan(0));
      expect(w.returnTurns, 1);
      run(w, .3);
      expect(w.returnTurns, 1);
    },
  );

  test('returning charges respect cover and do not fast-forward on resume', () {
    final w = empty();
    final bolt = RaidBolt(
      const RaidVec(350, 1210),
      const RaidVec(620, 0),
      true,
      1,
      returnOrigin: const RaidVec(300, 1210),
    )..life = 2.7;
    w.bolts.add(bolt);
    w.setPaused(true);
    run(w, 3);
    expect(bolt.returnIn, .8);
    w.setPaused(false);
    run(w, .2);
    expect(w.bolts, isEmpty);
    expect(w.returnTurns, 0);
  });

  for (final level in [1, 2]) {
    test(
      'mirror shield tier $level reflects once, consumes protection and damages the shooter',
      () {
        final w = empty();
        final d = still(100, const RaidVec(350, 1320));
        w.drones.add(d);
        w.upgrades[RaidUpgrade.reflect] = level;
        w.shield();
        w.bolts.add(
          RaidBolt(const RaidVec(450, 1320), const RaidVec(400, 0), true, 1),
        );
        run(w, .6);
        expect(w.health, 6);
        expect(w.shieldCharges, 1);
        expect(w.reflectedBolts, 1);
        expect(d.hp, d.maxHp - (level == 2 ? 3 : 2));
      },
    );
  }

  test(
    'mirror needs an active charged shield; rays never become projectiles',
    () {
      final w = empty()..upgrades[RaidUpgrade.reflect] = 1;
      w.bolts.add(
        RaidBolt(const RaidVec(500, 1320), const RaidVec(400, 0), true, 1),
      );
      run(w, .2);
      expect(w.health, 5);
      expect(w.reflectedBolts, 0);
      w.immunity = 0;
      w.shield();
      w.beams.add(RaidBeam(const RaidVec(400, 1320), const RaidVec(700, 1320)));
      run(w, .02);
      expect(w.health, 5);
      expect(w.shieldCharges, 1);
      expect(w.reflectedBolts, 0);
    },
  );

  test('shock hits visible drones once per dash, leaves cover and guardian in place', () {
    final w = empty()
      ..player = const RaidVec(350, 1210)
      ..upgrades[RaidUpgrade.shock] = 2;
    final visible = still(100, const RaidVec(350, 1320));
    final covered = still(101, const RaidVec(570, 1210));
    w.drones.addAll([visible, covered]);
    expect(w.dash(), true);
    expect(w.shockHits, 1);
    expect(visible.hp, 97);
    expect(visible.position.y, 1320);
    expect(covered.hp, 100);
    expect(w.dash(), false);
    run(w, .2);
    expect(visible.hp, 97);
    expect(w.shockHits, 1);
  });

  test('shock respects bulwark shield, knocks ordinary drones without crossing crates', () {
    final w = empty()..upgrades[RaidUpgrade.shock] = 1;
    final guarded = still(100, const RaidVec(650, 1320), RaidDroneKind.bulwark);
    final normal = still(101, const RaidVec(600, 1370), RaidDroneKind.scout);
    w.drones.addAll([guarded, normal]);
    final before = normal.position;
    w.dash();
    expect(guarded.hp, 8);
    expect(normal.hp, 3);
    expect(normal.position.distance(before), greaterThan(50));
    expect(w.blocks.any((b) => b.contains(normal.position, 31.9)), false);
    w.setPaused(true);
    final life = w.shockwaves.single.life;
    run(w, 2);
    expect(w.shockwaves.single.life, life);
  });
}
