import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/engagement/ray_raid_model.dart';

void main() {
  void run(RayRaidWorld w, double seconds) {
    for (var i = 0; i < (seconds * 120).ceil(); i++) {
      w.advance(1 / 120);
    }
  }

  RayRaidWorld empty([RaidMission mission = RaidMission.rescue]) {
    final w = RayRaidWorld(mission: mission)..start();
    w.drones.clear();
    w.coreUnlocked = true;
    w.player = const RaidVec(700, 1100);
    return w;
  }

  RaidDrone still(int id, RaidVec at) =>
      RaidDrone(id, RaidDroneKind.relay, at)..arrival = 0;

  test(
    'only the current rescue bot can be picked up and energy needs delivery',
    () {
      final w = empty();
      w.player = raidRescueBots[1];
      run(w, .02);
      expect(w.carriedRescue, isNull);
      w.player = raidCores[0];
      run(w, .02);
      expect(w.coreCount, 0);
      expect(w.phase, RaidPhase.playing);
      w.player = raidRescueBots[0];
      run(w, .02);
      expect(w.carriedRescue, 0);
      expect(w.rescuePickups, 1);
      expect(w.rescueReady, false);
      expect(w.movementSpeed, 185);
      run(w, .1);
      expect(w.rescuePickups, 1);
      w.player = raidCores[0];
      run(w, .02);
      expect(w.carriedRescue, isNull);
      expect(w.rescuedBots, {0});
      expect(w.coreCount, 1);
      expect(w.phase, RaidPhase.upgrade);
      expect(w.movementSpeed, 215);
    },
  );

  test('rescue does not skip either combat wave or grant a module', () {
    final w = RayRaidWorld(mission: RaidMission.rescue)..start();
    w.player = raidRescueBots[0];
    run(w, .02);
    w.player = raidCores[0];
    run(w, .02);
    expect(w.rescuedBots, {0});
    expect(w.coreCount, 0);
    expect(w.moduleCount, 0);
    expect(w.phase, RaidPhase.playing);
    expect(w.drones, isNotEmpty);
  });

  test('carrying uses ordinary collision and still permits a normal dash', () {
    final w = empty()..player = raidRescueBots[0];
    run(w, .02);
    w.player = const RaidVec(700, 1100);
    w.setMove(const RaidVec(-1, 0));
    run(w, .1);
    expect(w.player.x, closeTo(681.5, .2));
    w.dash();
    run(w, .1);
    expect(w.player.x, lessThan(600));
    expect(w.carriedRescue, 0);
    expect(w.blocks.any((b) => b.contains(w.player, 21.9)), false);
  });

  test(
    'meteor warns first, locks its target, then hits player and drone once',
    () {
      final w = empty(RaidMission.meteor)..meteorCountdown = 100;
      final target = const RaidVec(700, 1100);
      final d = still(100, const RaidVec(780, 1100));
      w.drones.add(d);
      w.meteors.add(RaidMeteor(target));
      run(w, 1);
      expect(w.health, 6);
      expect(d.hp, 12);
      run(w, .35);
      expect(w.health, 5);
      expect(d.hp, 9);
      expect(w.meteorStrikes, 1);
      expect(w.meteorDroneHits, 1);
      run(w, .3);
      expect(w.health, 5);
      expect(d.hp, 9);
      expect(w.meteorStrikes, 1);
    },
  );

  test(
    'moving out of a meteor mark avoids damage and warnings remain bounded',
    () {
      final w = empty(RaidMission.meteor)..meteorCountdown = 0;
      run(w, .02);
      expect(w.meteors, hasLength(1));
      final marked = w.meteors.single.position;
      w.player = const RaidVec(950, 1100);
      run(w, 1.4);
      expect(w.health, 6);
      expect(w.meteorStrikes, 1);
      expect(marked.x, 700);
      expect(marked.y, 1100);
      w.meteors.clear();
      for (var i = 0; i < 4; i++) {
        w.meteors.add(RaidMeteor(marked)..delay = 10);
      }
      w.meteorCountdown = 0;
      run(w, .02);
      expect(w.meteors, hasLength(4));
    },
  );

  test(
    'pause freezes meteor warnings, ring growth, flight and guard recharge',
    () {
      final w = empty(RaidMission.meteor)
        ..meteorCountdown = 100
        ..orbitCooldown = 2;
      w.meteors.add(RaidMeteor(w.player));
      w.pulseRings.add(RaidPulseRing(w.player));
      final d = RaidDrone(100, RaidDroneKind.hopper, const RaidVec(500, 1100))
        ..arrival = 0
        ..jumpFrom = const RaidVec(500, 1100)
        ..jumpTarget = w.player
        ..jumpTime = .65;
      w.drones.add(d);
      w.setPaused(true);
      w.advance(100);
      expect(w.meteors.single.delay, 1.3);
      expect(w.pulseRings.single.radius, 0);
      expect(d.jumpTime, .65);
      expect(w.orbitCooldown, 2);
      expect(w.health, 6);
    },
  );

  test('pulsar has a visible windup before a bounded expanding ring', () {
    final w = empty();
    final d = RaidDrone(100, RaidDroneKind.pulsar, const RaidVec(500, 1100))
      ..arrival = 0
      ..cooldown = 0;
    w.drones.add(d);
    run(w, .02);
    expect(d.windup, greaterThan(.85));
    expect(w.pulseRings, isEmpty);
    run(w, .8);
    expect(w.pulseRings, isEmpty);
    run(w, .2);
    expect(w.pulseAttacks, 1);
    expect(w.pulseRings, hasLength(1));
    expect(w.pulseRings.single.radius, greaterThan(0));
  });

  test('an expanding ring damages only on crossing and never twice', () {
    final w = empty();
    w.pulseRings.add(RaidPulseRing(const RaidVec(500, 1100)));
    run(w, 1.1);
    expect(w.health, 5);
    w.player = const RaidVec(760, 1100);
    run(w, 1);
    expect(w.health, 5);
    expect(w.pulseRings, isEmpty);
  });

  test(
    'hopper locks a clear landing and does not retarget after the warning',
    () {
      final w = empty()..player = const RaidVec(740, 1100);
      final d = RaidDrone(100, RaidDroneKind.hopper, const RaidVec(520, 1100))
        ..arrival = 0
        ..cooldown = 0;
      w.drones.add(d);
      run(w, .02);
      final target = d.jumpTarget;
      expect(d.windup, greaterThan(.85));
      expect(w.blocks.any((b) => b.contains(target, 31.9)), false);
      w.player = const RaidVec(950, 1100);
      run(w, 1.55);
      expect(d.jumpTarget.x, target.x);
      expect(d.jumpTarget.y, target.y);
      expect(w.jumpAttacks, 1);
      expect(w.jumpLandings, 1);
      expect(d.position.distance(target), lessThan(8));
      expect(w.health, 6);
    },
  );

  test(
    'a ricochet shot bounces from cover and can hit a drone on its return',
    () {
      final w = empty();
      final d = still(100, const RaidVec(275, 1220));
      w.drones.add(d);
      w.bolts.add(
        RaidBolt(
          const RaidVec(370, 1220),
          const RaidVec(620, 0),
          false,
          1,
          ricochets: 1,
        ),
      );
      run(w, .35);
      expect(w.ricochetBounces, 1);
      expect(d.hp, 11);
    },
  );

  test('a selected ricochet module changes real fired shots', () {
    final w = empty()..phase = RaidPhase.upgrade;
    expect(w.selectUpgrade(RaidUpgrade.ricochet), true);
    w.drones.clear();
    w.coreUnlocked = true;
    w.player = const RaidVec(350, 1220);
    w.setAim(const RaidVec(1, 0), shooting: true);
    run(w, .2);
    expect(w.ricochetBounces, greaterThan(0));
  });

  test('arena wall bounces keep a finite shot inside the arena', () {
    final w = empty();
    final b = RaidBolt(
      const RaidVec(25, 300),
      const RaidVec(-620, 0),
      false,
      1,
      ricochets: 2,
    );
    w.bolts.add(b);
    run(w, .02);
    expect(b.velocity.x, greaterThan(0));
    expect(b.position.x, greaterThanOrEqualTo(20));
    expect(b.position.finite, true);
    expect(b.ricochets, 1);
  });

  test(
    'the ricochet muzzle stays outside cover when pressed against a crate',
    () {
      final w = empty()..upgrades[RaidUpgrade.ricochet] = 1;
      w.player = const RaidVec(373, 1220);
      w.setAim(const RaidVec(1, 0), shooting: true);
      run(w, .02);
      expect(w.ricochetBounces, greaterThan(0));
      expect(w.bolts.every((b) => b.velocity.x < 0), true);
    },
  );

  test(
    'shock damages an airborne hopper without displacing its fixed flight',
    () {
      final w = empty()..upgrades[RaidUpgrade.shock] = 1;
      w.player = const RaidVec(650, 1100);
      final d = RaidDrone(100, RaidDroneKind.hopper, const RaidVec(600, 1100))
        ..arrival = 0
        ..jumpFrom = const RaidVec(500, 1100)
        ..jumpTarget = const RaidVec(700, 1100)
        ..jumpTime = .3;
      w.drones.add(d);
      w.dash();
      expect(d.hp, 5);
      expect(d.position.x, 600);
      run(w, .31);
      expect(w.jumpLandings, 1);
      expect(d.position.distance(d.jumpTarget), lessThan(5));
    },
  );

  test('a cover corner reverses both axes without trapping the projectile', () {
    final w = empty();
    final b = RaidBolt(
      const RaidVec(345, 1130),
      const RaidVec(620, 620),
      false,
      1,
      ricochets: 1,
    );
    w.bolts.add(b);
    run(w, .1);
    expect(w.ricochetBounces, 1);
    expect(b.velocity.x, lessThan(0));
    expect(b.velocity.y, lessThan(0));
    expect(w.blocks.any((x) => x.contains(b.position, 3.9)), false);
  });

  test('shots without ricochets do not pass through cover', () {
    final w = empty();
    final d = still(100, const RaidVec(620, 1220));
    w.drones.add(d);
    w.bolts.add(
      RaidBolt(const RaidVec(370, 1220), const RaidVec(620, 0), false, 1),
    );
    run(w, .6);
    expect(w.ricochetBounces, 0);
    expect(d.hp, 12);
    expect(w.bolts, isEmpty);
  });

  test(
    'orbital guard intercepts one charge, preserves shield, then recharges',
    () {
      final w = empty()..upgrades[RaidUpgrade.orbit] = 1;
      w.shield();
      final charges = w.shieldCharges;
      void shot() => w.bolts.add(
        RaidBolt(
          w.player + const RaidVec(-100, 0),
          const RaidVec(175, 0),
          true,
          1,
        ),
      );
      shot();
      run(w, .1);
      expect(w.orbitBlocks, 1);
      expect(w.shieldCharges, charges);
      expect(w.health, 6);
      shot();
      run(w, .5);
      expect(w.orbitBlocks, 1);
      expect(w.shieldCharges, charges - 1);
      run(w, 2.6);
      shot();
      run(w, .1);
      expect(w.orbitBlocks, 2);
    },
  );

  test(
    'second guard tier intercepts at a greater distance and recharges faster',
    () {
      final a = empty()..upgrades[RaidUpgrade.orbit] = 1;
      final b = empty()..upgrades[RaidUpgrade.orbit] = 2;
      for (final w in [a, b]) {
        w.bolts.add(
          RaidBolt(
            w.player + const RaidVec(-105, 0),
            const RaidVec(175, 0),
            true,
            1,
          ),
        );
        run(w, .01);
      }
      expect(a.orbitBlocks, 0);
      expect(b.orbitBlocks, 1);
      expect(b.orbitCooldown, lessThanOrEqualTo(1.8));
    },
  );

  test('the guard protects from charges, not expanding energy waves', () {
    final w = empty()..upgrades[RaidUpgrade.orbit] = 2;
    w.pulseRings.add(RaidPulseRing(const RaidVec(600, 1100))..radius = 100);
    run(w, .02);
    expect(w.orbitBlocks, 0);
    expect(w.health, 5);
  });
}
