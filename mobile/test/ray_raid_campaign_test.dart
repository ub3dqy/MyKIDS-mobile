import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/engagement/ray_raid_model.dart';

import 'support/ray_raid_pilot.dart';

void main() {
  void run(RayRaidWorld world, double seconds) {
    for (var frame = 0; frame < (seconds * 120).ceil(); frame++) {
      world.advance(1 / 120);
    }
  }

  RaidDrone drone(int id, RaidDroneKind kind, RaidVec at) =>
      RaidDrone(id, kind, at)..arrival = 0;

  for (final mission in RaidMission.values) {
    test(
      '${mission.name}: distinct geometry has reachable objectives and clear spawns',
      () {
        final world = RayRaidWorld(mission: mission)..start();
        for (final point in [raidStart, ...raidCores, raidBeacon]) {
          expect(world.blocks.any((b) => b.contains(point, 32)), false);
        }
        final pilot = RaidPilot();
        var player = raidStart;
        for (final target in [...raidCores, raidBeacon]) {
          for (
            var step = 0;
            step < 4000 && player.distance(target) > 20;
            step++
          ) {
            player = world.move(
              player,
              pilot.toward(player, target, blocks: world.blocks) * 4,
              22,
            );
          }
          expect(player.distance(target), lessThan(21));
        }
        for (final d in world.drones) {
          expect(
            world.blocks.any((b) => b.contains(d.position, d.radius)),
            false,
          );
        }
      },
    );

    for (final build in [
      [RaidUpgrade.companion, RaidUpgrade.pulse, RaidUpgrade.shield],
      [RaidUpgrade.pierce, RaidUpgrade.pulse, RaidUpgrade.dash],
      [RaidUpgrade.frost, RaidUpgrade.chain, RaidUpgrade.shield],
      [RaidUpgrade.reflect, RaidUpgrade.shock, RaidUpgrade.pulse],
      [RaidUpgrade.ricochet, RaidUpgrade.orbit, RaidUpgrade.pulse],
      [RaidUpgrade.orbit, RaidUpgrade.ricochet, RaidUpgrade.shield],
    ]) {
      test(
        '${mission.name}: ordinary controls complete ${build.first.name} build',
        () {
          final world = RayRaidWorld(mission: mission)..start();
          final pilot = RaidPilot();
          final kinds = <RaidDroneKind>{};
          for (
            var frame = 0;
            frame < 120 * 240 &&
                world.phase != RaidPhase.won &&
                world.phase != RaidPhase.lost;
            frame++
          ) {
            kinds.addAll(world.drones.map((d) => d.kind));
            if (world.phase == RaidPhase.upgrade) {
              world.selectUpgrade(build[world.coreCount - 1]);
            }
            if (frame % 12 == 0) {
              final movement = pilot.movement(world);
              world.setMove(movement);
              world.setAim(pilot.fireAim(world), shooting: true);
              if (pilot.danger(world)) {
                world.shield();
              }
              if (pilot.shouldDash(world)) world.dash();
            }
            world.advance(1 / 120);
            expect(world.bolts.length, lessThanOrEqualTo(64));
            expect(world.particles.length, lessThanOrEqualTo(96));
            expect(world.drones.length, lessThanOrEqualTo(7));
            expect(
              world.blocks.any((b) => b.contains(world.player, 21.9)),
              false,
            );
            expect(world.player.finite, true);
          }
          expect(
            world.phase,
            RaidPhase.won,
            reason:
                '${world.objective}, ${world.elapsed}s, hp ${world.health}, position ${world.player.x},${world.player.y}, drones ${world.drones.map((d) => '${d.kind}:${d.hp}@${d.position.x},${d.position.y}')}',
          );
          expect(world.moduleCount, 3);
          expect(world.disabledDrones, 17);
          expect(world.relaysDisabled, mission == RaidMission.dock ? 4 : 0);
          if (mission == RaidMission.foundry || mission == RaidMission.dock) {
            expect(
              kinds,
              containsAll([RaidDroneKind.interceptor, RaidDroneKind.repairer]),
            );
          }
          if (mission == RaidMission.convoy || mission == RaidMission.storm) {
            expect(
              kinds,
              containsAll([RaidDroneKind.prism, RaidDroneKind.bomber]),
            );
            expect(world.beamAttacks, greaterThan(0));
            expect(world.blastAttacks, greaterThan(0));
          }
          if (mission == RaidMission.convoy) {
            expect(world.convoy.health, greaterThan(0));
            expect(world.convoy.position.distance(raidBeacon), lessThan(3));
          }
          if (mission == RaidMission.storm) {
            expect(world.antennaCharge, everyElement(4));
          }
          if (mission == RaidMission.portal || mission == RaidMission.magnet) {
            expect(
              kinds,
              containsAll([RaidDroneKind.bulwark, RaidDroneKind.boomerang]),
            );
            expect(world.returnAttacks, greaterThan(0));
            expect(world.returnTurns, greaterThan(0));
          }
          if (mission == RaidMission.portal) expect(world.portalHops, 3);
          if (mission == RaidMission.magnet) {
            expect(world.conveyorSteps, greaterThan(0));
          }
          if (mission == RaidMission.rescue || mission == RaidMission.meteor) {
            expect(
              kinds,
              containsAll([RaidDroneKind.pulsar, RaidDroneKind.hopper]),
            );
            expect(world.pulseAttacks, greaterThan(0));
            expect(world.jumpAttacks, greaterThan(0));
            expect(world.jumpLandings, greaterThan(0));
          }
          if (mission == RaidMission.rescue) {
            expect(world.rescuedBots, {0, 1, 2});
            expect(world.rescuePickups, 3);
            expect(world.carriedRescue, isNull);
          }
          if (mission == RaidMission.meteor) {
            expect(world.meteorStrikes, greaterThan(0));
          }
          if (build.contains(RaidUpgrade.ricochet)) {
            expect(world.ricochetBounces, greaterThan(0));
          }
        },
      );
    }
  }

  test('read-only pilot recognizes a charge aimed at the cargo and shared shield protects it', () {
    final world = RayRaidWorld(mission: RaidMission.convoy)..start();
    world.drones.clear();
    world.coreUnlocked = true;
    world.convoy.position = raidConvoyRoute[raidConvoyStops[0]];
    world.convoy.waypoint = raidConvoyStops[0] + 1;
    world.player = world.convoy.position + const RaidVec(200, 0);
    world.bolts.add(
      RaidBolt(
        world.convoy.position + const RaidVec(-120, 0),
        const RaidVec(175, 0),
        true,
        1,
      ),
    );
    expect(RaidPilot().danger(world), true);
    world.shield();
    final charges = world.shieldCharges;
    run(world, 1);
    expect(world.convoy.health, 8);
    expect(world.shieldCharges, charges - 1);
    expect(world.health, 6);
  });

  test('interceptor warns, locks its charge, then stops at cover', () {
    final world = RayRaidWorld(mission: RaidMission.foundry)..start();
    world.player = const RaidVec(560, 1100);
    final d = drone(100, RaidDroneKind.interceptor, const RaidVec(560, 1350))
      ..cooldown = 0;
    world.drones
      ..clear()
      ..add(d);
    run(world, .02);
    expect(d.windup, greaterThan(.6));
    final aim = d.aim;
    final waiting = d.position;
    world.player = const RaidVec(620, 1100);
    run(world, .5);
    expect(d.position.y, waiting.y);
    expect(d.aim.x, aim.x);
    expect(d.aim.y, aim.y);
    run(world, .5);
    expect(d.attack, 1);
    expect(d.position.y, lessThan(1350));
    expect(
      world.blocks.any((b) => b.contains(d.position, d.radius - .1)),
      false,
    );
    d.position = const RaidVec(330, 1210);
    d.aim = const RaidVec(1, 0);
    d.windup = .001;
    d.chargeTime = 0;
    run(world, .5);
    expect(d.position.x, lessThanOrEqualTo(340));
  });

  test(
    'repairer heals a visible ally within a cap and cannot heal through cover',
    () {
      final world = RayRaidWorld(mission: RaidMission.foundry)..start();
      world.player = const RaidVec(900, 1300);
      final healer = drone(
        100,
        RaidDroneKind.repairer,
        const RaidVec(650, 1300),
      )..cooldown = 0;
      final ally = drone(101, RaidDroneKind.sentry, const RaidVec(620, 1370))
        ..hp = 7;
      world.drones
        ..clear()
        ..addAll([healer, ally]);
      run(world, .02);
      expect(ally.hp, ally.maxHp);
      expect(world.repairedPulses, 1);
      expect(healer.repairTarget, isNotNull);
      ally.hp = 3;
      healer.position = const RaidVec(350, 1220);
      ally.position = const RaidVec(570, 1220);
      healer.cooldown = 0;
      run(world, .02);
      expect(ally.hp, 3);
      expect(world.repairedPulses, 1);
    },
  );

  test('relay shields allies, assisted aim picks the relay, destruction releases shield', () {
    final world = RayRaidWorld(mission: RaidMission.dock)..start();
    world.player = const RaidVec(560, 1350);
    final relay = drone(100, RaidDroneKind.relay, const RaidVec(650, 1350));
    final ally = drone(101, RaidDroneKind.scout, const RaidVec(560, 1280));
    world.drones
      ..clear()
      ..addAll([relay, ally]);
    world.bolts.add(RaidBolt(ally.position, RaidVec.zero, false, 9));
    run(world, .02);
    expect(ally.hp, ally.maxHp);
    world.setAim(RaidVec.zero, shooting: true);
    run(world, .15);
    expect(world.facing.x, greaterThan(.9));
    expect(relay.hp, lessThan(relay.maxHp));
    world.bolts.add(RaidBolt(relay.position, RaidVec.zero, false, 100));
    run(world, .02);
    expect(world.relayAlive, false);
    expect(world.relaysDisabled, 1);
    expect(world.shielded(ally), false);
  });

  test('solar traps always give a warning; pause freezes the cycle; shield absorbs discharge', () {
    final world = RayRaidWorld(mission: RaidMission.foundry)..start();
    final hazard = world.hazards.first;
    world.player = hazard.position;
    world.elapsed = 3.8;
    expect(hazard.warning(world.elapsed), true);
    run(world, .9);
    expect(world.health, 6);
    world.setPaused(true);
    run(world, 5);
    expect(hazard.active(world.elapsed), false);
    world.setPaused(false);
    world.shield();
    run(world, .2);
    expect(hazard.active(world.elapsed), true);
    expect(world.health, 6);
    expect(world.shieldCharges, lessThan(2));
    world.collected.add(0);
    expect(world.hazardCooled(hazard), true);
    expect(world.hazardActive(hazard), false);
    world.shieldTime = 0;
    world.immunity = 0;
    run(world, .2);
    expect(world.health, 6);
  });

  test('companion has a real fire rate, no shots through cover and freezes in pause', () {
    final world = RayRaidWorld()..start();
    world.upgrades[RaidUpgrade.companion] = 1;
    final ally = drone(100, RaidDroneKind.guardian, const RaidVec(700, 1350));
    world.drones
      ..clear()
      ..add(ally);
    run(world, .7);
    expect(ally.hp, lessThan(ally.maxHp));
    expect(world.firing, false);
    final count = world.bolts.length, elapsed = world.elapsed;
    world.setPaused(true);
    run(world, 10);
    expect(world.elapsed, elapsed);
    expect(world.bolts.length, count);
    world.setPaused(false);
    world.player = const RaidVec(350, 1200);
    ally.position = const RaidVec(600, 1200);
    world.bolts.clear();
    world.elapsed = 0;
    world.companionCooldown = 0;
    run(world, .02);
    expect(world.bolts.where((b) => !b.hostile), isEmpty);
  });

  test('piercing charges hit each enemy once, stop after their allowance and respect cover', () {
    final world = RayRaidWorld()..start();
    world.player = const RaidVec(560, 1400);
    final a = drone(100, RaidDroneKind.guardian, const RaidVec(300, 1340));
    final b = drone(101, RaidDroneKind.guardian, const RaidVec(400, 1340));
    final c = drone(102, RaidDroneKind.guardian, const RaidVec(500, 1340));
    world.drones
      ..clear()
      ..addAll([a, b, c]);
    world.bolts.add(
      RaidBolt(
        const RaidVec(200, 1340),
        const RaidVec(620, 0),
        false,
        1,
        pierces: 1,
      ),
    );
    run(world, .6);
    expect(a.hp, 99);
    expect(b.hp, 99);
    expect(c.hp, 100);
    world.bolts.add(
      RaidBolt(
        const RaidVec(350, 1210),
        const RaidVec(620, 0),
        false,
        100,
        pierces: 2,
      ),
    );
    run(world, .5);
    expect(world.bolts.where((b) => !b.hostile), isEmpty);
    expect(c.hp, 100);
  });
}
