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
  RaidDrone still(int id, RaidVec at) =>
      RaidDrone(id, RaidDroneKind.guardian, at)
        ..arrival = 0
        ..windup = 100;

  test('convoy rail segments have real vehicle clearance', () {
    final w = RayRaidWorld(mission: RaidMission.convoy);
    var previous = raidConvoyStart;
    for (final point in raidConvoyRoute) {
      expect(
        w.lineBlocked(previous, point, 31),
        false,
        reason: '${point.x},${point.y}',
      );
      previous = point;
    }
  });
  test('convoy requires a nearby escort, stops at the current node and freezes on pause', () {
    final w = empty(RaidMission.convoy);
    run(w, 1);
    expect(w.convoy.position.distance(raidConvoyStart), greaterThan(80));
    w.player = const RaidVec(1000, 150);
    final position = w.convoy.position;
    run(w, 1);
    expect(w.convoy.position.distance(position), 0);
    w.player = w.convoy.position;
    w.setPaused(true);
    run(w, 5);
    expect(w.convoy.position.distance(position), 0);
    w.setPaused(false);
    for (var frame = 0; frame < 4000 && w.phase == RaidPhase.playing; frame++) {
      w.player = w.convoy.position;
      w.advance(1 / 120);
    }
    expect(w.phase, RaidPhase.upgrade);
    expect(w.coreCount, 1);
    expect(w.convoy.position.distance(raidCores[0]), lessThan(3));
    final stopped = w.convoy.position;
    run(w, .5);
    expect(w.convoy.position.distance(stopped), 0);
  });
  test('nearby shield protects the convoy; a distant shield does not', () {
    final w = empty(RaidMission.convoy);
    w.convoy.position = const RaidVec(560, 1320);
    w.player = const RaidVec(650, 1350);
    w.shield();
    w.bolts.add(
      RaidBolt(
        w.convoy.position + const RaidVec(0, 70),
        const RaidVec(0, -700),
        true,
        1,
      ),
    );
    run(w, .13);
    expect(w.convoy.health, 8);
    expect(w.shieldCharges, 1);
    w.player = const RaidVec(950, 1400);
    w.convoy.immunity = 0;
    w.bolts.add(
      RaidBolt(
        w.convoy.position + const RaidVec(0, 70),
        const RaidVec(0, -700),
        true,
        1,
      ),
    );
    run(w, .13);
    expect(w.convoy.health, 7);
  });
  test('disabled convoy ends the run and cannot restart itself', () {
    final w = empty(RaidMission.convoy);
    w.convoy.health = 1;
    w.beams.add(
      RaidBeam(
        w.convoy.position + const RaidVec(-100, 0),
        w.convoy.position + const RaidVec(100, 0),
      ),
    );
    run(w, .02);
    expect(w.convoy.health, 0);
    expect(w.phase, RaidPhase.lost);
    final elapsed = w.elapsed;
    w.start();
    run(w, 10);
    expect(w.elapsed, elapsed);
    expect(w.shield(), false);
  });
  test('antenna keeps partial charge outside its circle and on pause', () {
    final w = empty(RaidMission.storm)..player = raidCores[0];
    run(w, 2);
    final charge = w.antennaCharge[0];
    expect(charge, closeTo(2, .02));
    expect(w.coreCount, 0);
    w.player = raidStart;
    run(w, 1);
    expect(w.antennaCharge[0], charge);
    w.setPaused(true);
    run(w, 10);
    expect(w.antennaCharge[0], charge);
    w.setPaused(false);
    w.player = raidCores[0];
    run(w, 2.1);
    expect(w.antennaCharge[0], 4);
    expect(w.phase, RaidPhase.upgrade);
    expect(w.coreCount, 1);
  });
  test('charging an antenna cannot skip either combat wave', () {
    final w = RayRaidWorld(mission: RaidMission.storm)
      ..start()
      ..player = raidCores[0];
    for (final d in w.drones) {
      d.arrival = 100;
    }
    run(w, 4.1);
    expect(w.antennaCharge[0], 4);
    expect(w.coreUnlocked, false);
    expect(w.coreCount, 0);
  });
  test('prism locks a full warning before its cover-clipped beam and hits only once', () {
    final w = empty()..player = const RaidVec(560, 1300);
    final d = RaidDrone(100, RaidDroneKind.prism, const RaidVec(560, 1100))
      ..arrival = 0
      ..cooldown = 0;
    w.drones.add(d);
    run(w, .02);
    expect(d.windup, greaterThan(.9));
    final aim = d.aim;
    w.player = const RaidVec(620, 1300);
    run(w, .9);
    expect(w.beams, isEmpty);
    expect(w.health, 6);
    expect(d.aim.x, aim.x);
    expect(d.aim.y, aim.y);
    run(w, .15);
    expect(w.beams, hasLength(1));
    w.player = const RaidVec(560, 1300);
    run(w, .05);
    expect(w.health, 5);
    run(w, .1);
    expect(w.health, 5);
    expect(w.rayEnd(const RaidVec(300, 1200), const RaidVec(1, 0)).x, 390);
    expect(w.rayEnd(const RaidVec(560, 1350), const RaidVec(1, 0)).x, 1085);
  });
  test(
    'bomber gives a fixed ground warning and moving away avoids its discharge',
    () {
      final w = empty()..player = const RaidVec(560, 1350);
      final d = RaidDrone(100, RaidDroneKind.bomber, const RaidVec(560, 1100))
        ..arrival = 0
        ..cooldown = 0;
      w.drones.add(d);
      run(w, .75);
      expect(w.blasts, hasLength(1));
      expect(w.blasts.single.delay, greaterThan(.8));
      final marked = w.blasts.single.position;
      w.player = const RaidVec(900, 1350);
      run(w, .85);
      expect(w.blasts.single.position.distance(marked), 0);
      expect(w.health, 6);
      run(w, .4);
      expect(w.health, 6);
      expect(w.blasts, isEmpty);
    },
  );
  test('frost slows nearby visible enemies and charges only while a charged shield is active', () {
    final w = empty()..player = const RaidVec(560, 1350);
    w.upgrades[RaidUpgrade.frost] = 1;
    expect(w.enemyTimeScale(const RaidVec(560, 1200)), 1);
    w.shield();
    expect(w.enemyTimeScale(const RaidVec(560, 1200)), .55);
    final bolt = RaidBolt(
      const RaidVec(560, 1200),
      const RaidVec(0, -100),
      true,
      1,
    );
    w.bolts.add(bolt);
    run(w, .1);
    expect(bolt.position.y, closeTo(1194.5, .1));
    w.upgrades[RaidUpgrade.frost] = 2;
    expect(w.enemyTimeScale(const RaidVec(560, 1120)), .35);
    expect(w.enemyTimeScale(const RaidVec(450, 1200)), 1);
    w.shieldCharges = 0;
    expect(w.enemyTimeScale(const RaidVec(560, 1200)), 1);
  });
  test('chain strikes at most one then two visible neighbors without repeated damage', () {
    final w = empty()..player = const RaidVec(560, 1400);
    final a = still(100, const RaidVec(300, 1340));
    final b = still(101, const RaidVec(400, 1340));
    final c = still(102, const RaidVec(500, 1340));
    w.drones.addAll([a, b, c]);
    w.upgrades[RaidUpgrade.chain] = 1;
    w.bolts.add(
      RaidBolt(const RaidVec(200, 1340), const RaidVec(620, 0), false, 1),
    );
    run(w, .2);
    expect(a.hp, 99);
    expect(b.hp, 99);
    expect(c.hp, 100);
    expect(w.chainHits, 1);
    w.upgrades[RaidUpgrade.chain] = 2;
    w.bolts.add(
      RaidBolt(const RaidVec(200, 1340), const RaidVec(620, 0), false, 1),
    );
    run(w, .2);
    expect(a.hp, 98);
    expect(b.hp, 98);
    expect(c.hp, 99);
    expect(w.chainHits, 3);
  });
  test('chain never crosses solid cover or bypasses a relay field', () {
    final w = empty()..player = const RaidVec(300, 1350);
    final a = still(100, const RaidVec(350, 1210)),
        b = still(101, const RaidVec(580, 1210));
    w.drones.addAll([a, b]);
    w.upgrades[RaidUpgrade.chain] = 2;
    w.bolts.add(
      RaidBolt(const RaidVec(280, 1210), const RaidVec(620, 0), false, 1),
    );
    run(w, .2);
    expect(a.hp, 98);
    expect(b.hp, 100);
    expect(w.chainHits, 0);
    final dock = empty(RaidMission.dock)..player = const RaidVec(560, 1350);
    dock.upgrades[RaidUpgrade.chain] = 2;
    final relay = RaidDrone(100, RaidDroneKind.relay, const RaidVec(650, 1350))
      ..arrival = 0;
    final ally = still(101, const RaidVec(700, 1350));
    dock.drones.addAll([relay, ally]);
    dock.bolts.add(RaidBolt(relay.position, RaidVec.zero, false, 1));
    run(dock, .02);
    expect(ally.hp, 100);
    expect(dock.chainHits, 0);
  });
  test(
    'pause freezes queued blasts, active beams, convoy and all module effects',
    () {
      final w = empty(RaidMission.convoy);
      w.blasts.add(RaidBlast(const RaidVec(800, 1400)));
      w.beams.add(RaidBeam(const RaidVec(100, 200), const RaidVec(300, 200)));
      w.arcs.add(RaidArc(const RaidVec(100, 200), const RaidVec(200, 200)));
      w.setPaused(true);
      run(w, 20);
      expect(w.blasts.single.delay, .95);
      expect(w.beams.single.life, .32);
      expect(w.arcs.single.life, .18);
      expect(w.convoy.position.distance(raidConvoyStart), 0);
    },
  );
}
