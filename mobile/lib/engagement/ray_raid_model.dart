import 'dart:math' as math;

/// A bounded, local simulation. It has no repository, clock, storage or rewards.
class RaidVec {
  final double x, y;
  const RaidVec(this.x, this.y);
  static const zero = RaidVec(0, 0);
  RaidVec operator +(RaidVec b) => RaidVec(x + b.x, y + b.y);
  RaidVec operator -(RaidVec b) => RaidVec(x - b.x, y - b.y);
  RaidVec operator *(double n) => RaidVec(x * n, y * n);
  double get length => math.sqrt(x * x + y * y);
  bool get finite => x.isFinite && y.isFinite;
  RaidVec get unit => length > .0001 && finite ? this * (1 / length) : zero;
  RaidVec get limited => finite ? (length > 1 ? unit : this) : zero;
  double distance(RaidVec b) => (this - b).length;
  RaidVec rotated(double a) => RaidVec(
    x * math.cos(a) - y * math.sin(a),
    x * math.sin(a) + y * math.cos(a),
  );
}

class RaidBlock {
  final double x, y, width, height;
  const RaidBlock(this.x, this.y, this.width, this.height);
  RaidVec get center => RaidVec(x + width / 2, y + height / 2);
  bool contains(RaidVec p, [double radius = 0]) =>
      p.x > x - radius &&
      p.x < x + width + radius &&
      p.y > y - radius &&
      p.y < y + height + radius;
}

enum RaidPhase { ready, playing, upgrade, won, lost }

enum RaidDroneKind {
  scout,
  sentry,
  interceptor,
  repairer,
  relay,
  guardian,
  prism,
  bomber,
  bulwark,
  boomerang,
  pulsar,
  hopper,
}

enum RaidUpgrade {
  pulse,
  dash,
  shield,
  companion,
  pierce,
  frost,
  chain,
  reflect,
  shock,
  ricochet,
  orbit,
}

enum RaidMission {
  beacon,
  foundry,
  dock,
  convoy,
  storm,
  portal,
  magnet,
  rescue,
  meteor,
}

extension RaidMissionInfo on RaidMission {
  String get title => switch (this) {
    RaidMission.beacon => 'Лунный маяк',
    RaidMission.foundry => 'Солнечный завод',
    RaidMission.dock => 'Орбитальный док',
    RaidMission.convoy => 'Ледяной конвой',
    RaidMission.storm => 'Штормовой спутник',
    RaidMission.portal => 'Портальный лабиринт',
    RaidMission.magnet => 'Магнитная верфь',
    RaidMission.rescue => 'Орбита спасения',
    RaidMission.meteor => 'Метеоритный рубеж',
  };
  String get briefing => switch (this) {
    RaidMission.beacon =>
      'Верни свет станции: три энергоблока и Страж на финише.',
    RaidMission.foundry =>
      'Охлади завод. Обходи оранжевые разряды и уклоняйся от перехватчиков.',
    RaidMission.dock =>
      'Освободи док. Сначала отключай генераторы щита, затем остальных дронов.',
    RaidMission.convoy => 'Сопроводи грузового робота. Держись рядом: он едет по светящейся дорожке. Щит защищает вас обоих.',
    RaidMission.storm => 'Восстанови три антенны. Держись в светящемся круге для связи и уклоняйся от лучей и меток на полу.',
    RaidMission.portal => 'Пройди через три голубых портала — по одному в каждом секторе. Отключи дронов и забери энергию. Оранжевый круг у щитоносца — пора атаковать: его защита выключена.',
    RaidMission.magnet => 'Дорожки двигают Лучика по стрелкам. Используй их для манёвра. Заряды дронов-бумерангов возвращаются назад — следи за ними и после пролёта!',
    RaidMission.rescue => 'Спаси трёх маленьких роботов. Подойди к роботу и отнеси его к площадке энергоблока. Кнопки не нужны: Лучик подберёт и высадит друга сам. Затем отключи дронов и забери энергию.',
    RaidMission.meteor => 'Пройди метеоритный рубеж. Оранжевая метка заранее показывает место удара — успей отойти. От метеоритов ящики не защищают. Собери три энергоблока и включи станцию.',
  };
  String get victory => switch (this) {
    RaidMission.beacon => 'МАЯК ВКЛЮЧЁН!',
    RaidMission.foundry => 'ЗАВОД ОХЛАЖДЁН!',
    RaidMission.dock => 'ДОК СВОБОДЕН!',
    RaidMission.convoy => 'КОНВОЙ ДОСТАВЛЕН!',
    RaidMission.storm => 'СИГНАЛ ДОСТАВЛЕН!',
    RaidMission.portal => 'ПОРТАЛЫ НАСТРОЕНЫ!',
    RaidMission.magnet => 'ВЕРФЬ ЗАПУЩЕНА!',
    RaidMission.rescue => 'ВСЕ ДРУЗЬЯ СПАСЕНЫ!',
    RaidMission.meteor => 'РУБЕЖ ПРОЙДЕН!',
  };
  String get ending => switch (this) {
    RaidMission.beacon => 'Лучик вернул свет на станцию.',
    RaidMission.foundry =>
      'Лучик остановил перегрев. Солнечные роботы в порядке!',
    RaidMission.dock => 'Защита дока отключена. Корабли снова могут взлетать!',
    RaidMission.convoy =>
      'Грузовой робот привёз энергию. Станция снова согреется!',
    RaidMission.storm =>
      'Лучик наладил связь. Все роботы услышали сигнал помощи!',
    RaidMission.portal => 'Лучик проложил короткий путь. Роботы снова могут путешествовать между станциями!',
    RaidMission.magnet =>
      'Лучик запустил магнитные дорожки. Новые корабли готовы к полёту!',
    RaidMission.rescue =>
      'Три маленьких робота вернулись на станцию. Теперь команда снова вместе!',
    RaidMission.meteor =>
      'Лучик провёл корабли через метеоритный поток. Путь к станции открыт!',
  };
}

enum RaidEffectKind { shot, hit, dash, shield, core, drone, win }

const raidWorldWidth = 1120.0;
const raidWorldHeight = 1480.0;
const raidStart = RaidVec(560, 1320);
const raidBeacon = RaidVec(560, 170);
const raidCores = [RaidVec(250, 1130), RaidVec(890, 810), RaidVec(270, 440)];
const raidBlocks = [
  RaidBlock(390, 1160, 140, 100),
  RaidBlock(660, 1190, 130, 100),
  RaidBlock(110, 865, 170, 95),
  RaidBlock(430, 925, 180, 100),
  RaidBlock(690, 950, 150, 95),
  RaidBlock(700, 610, 150, 100),
  RaidBlock(400, 650, 140, 105),
  RaidBlock(95, 590, 140, 90),
  RaidBlock(440, 360, 150, 100),
  RaidBlock(760, 355, 140, 100),
];

const raidFoundryBlocks = [
  RaidBlock(365, 1170, 160, 90),
  RaidBlock(740, 1200, 140, 95),
  RaidBlock(120, 850, 180, 95),
  RaidBlock(535, 950, 150, 95),
  RaidBlock(735, 590, 150, 105),
  RaidBlock(380, 650, 160, 95),
  RaidBlock(105, 570, 150, 90),
  RaidBlock(420, 350, 170, 100),
  RaidBlock(790, 350, 135, 100),
];
const raidDockBlocks = [
  RaidBlock(400, 1170, 140, 95),
  RaidBlock(745, 1210, 140, 90),
  RaidBlock(100, 870, 170, 95),
  RaidBlock(430, 900, 160, 100),
  RaidBlock(710, 950, 160, 90),
  RaidBlock(700, 610, 150, 100),
  RaidBlock(380, 660, 140, 100),
  RaidBlock(90, 590, 155, 90),
  RaidBlock(440, 355, 150, 95),
  RaidBlock(780, 355, 140, 95),
];

const raidConvoyBlocks = [
  RaidBlock(400, 1160, 160, 100),
  RaidBlock(700, 1140, 140, 90),
  RaidBlock(110, 880, 120, 100),
  RaidBlock(450, 865, 140, 90),
  RaidBlock(670, 650, 110, 75),
  RaidBlock(400, 660, 130, 100),
  RaidBlock(100, 650, 120, 100),
  RaidBlock(400, 340, 150, 90),
  RaidBlock(100, 300, 120, 85),
  RaidBlock(760, 355, 140, 95),
];
const raidStormBlocks = [
  RaidBlock(400, 1170, 140, 95),
  RaidBlock(745, 1210, 140, 90),
  RaidBlock(100, 870, 170, 95),
  RaidBlock(420, 920, 160, 100),
  RaidBlock(710, 950, 160, 90),
  RaidBlock(700, 610, 150, 100),
  RaidBlock(380, 660, 140, 100),
  RaidBlock(90, 590, 155, 90),
  RaidBlock(440, 355, 150, 95),
  RaidBlock(780, 355, 140, 95),
];
const raidPortalBlocks = [
  RaidBlock(400, 1170, 140, 95),
  RaidBlock(720, 1230, 140, 90),
  RaidBlock(100, 880, 170, 90),
  RaidBlock(430, 920, 160, 95),
  RaidBlock(710, 960, 150, 80),
  RaidBlock(700, 610, 150, 100),
  RaidBlock(390, 650, 140, 100),
  RaidBlock(90, 590, 145, 90),
  RaidBlock(450, 350, 150, 95),
  RaidBlock(780, 340, 140, 50),
];
const raidMagnetBlocks = [
  RaidBlock(390, 1180, 140, 95),
  RaidBlock(745, 1220, 140, 90),
  RaidBlock(100, 880, 170, 85),
  RaidBlock(430, 930, 160, 95),
  RaidBlock(710, 960, 160, 90),
  RaidBlock(700, 610, 150, 100),
  RaidBlock(380, 660, 140, 100),
  RaidBlock(90, 590, 155, 90),
  RaidBlock(440, 355, 150, 95),
  RaidBlock(780, 355, 140, 95),
];

const raidRescueBlocks = [
  RaidBlock(395, 1180, 140, 90),
  RaidBlock(715, 1290, 140, 80),
  RaidBlock(100, 870, 170, 90),
  RaidBlock(430, 930, 160, 95),
  RaidBlock(730, 920, 150, 90),
  RaidBlock(720, 600, 145, 95),
  RaidBlock(390, 650, 140, 100),
  RaidBlock(90, 590, 145, 85),
  RaidBlock(450, 350, 150, 95),
  RaidBlock(780, 335, 140, 70),
];
const raidMeteorBlocks = [
  RaidBlock(400, 1180, 140, 95),
  RaidBlock(740, 1220, 140, 90),
  RaidBlock(105, 875, 165, 95),
  RaidBlock(420, 925, 155, 95),
  RaidBlock(720, 945, 155, 90),
  RaidBlock(710, 605, 145, 95),
  RaidBlock(385, 660, 140, 95),
  RaidBlock(90, 585, 150, 90),
  RaidBlock(435, 355, 150, 95),
  RaidBlock(785, 350, 140, 95),
];
const raidRescueBots = [
  RaidVec(845, 1220),
  RaidVec(260, 760),
  RaidVec(860, 470),
];

class RaidPulseRing {
  final RaidVec position;
  double radius = 0;
  bool hitPlayer = false;
  RaidPulseRing(this.position);
  static const speed = 190.0, limit = 300.0;
}

class RaidMeteor {
  final RaidVec position;
  double delay = 1.3, life = .4;
  bool impacted = false;
  RaidMeteor(this.position);
  static const radius = 85.0;
}

class RaidPortal {
  final RaidVec entry, exit;
  const RaidPortal(this.entry, this.exit);
}

const raidPortals = [
  RaidPortal(RaidVec(800, 1100), RaidVec(250, 1200)),
  RaidPortal(RaidVec(300, 760), RaidVec(890, 880)),
  RaidPortal(RaidVec(850, 450), RaidVec(270, 510)),
];

class RaidConveyor {
  final RaidBlock area;
  final RaidVec direction;
  const RaidConveyor(this.area, this.direction);
}

const raidConveyors = [
  RaidConveyor(RaidBlock(130, 1280, 560, 95), RaidVec(-1, 0)),
  RaidConveyor(RaidBlock(905, 760, 90, 430), RaidVec(0, -1)),
  RaidConveyor(RaidBlock(200, 490, 700, 90), RaidVec(1, 0)),
];

class RaidShockwave {
  final RaidVec position;
  final double radius;
  double life = .35;
  RaidShockwave(this.position, this.radius);
}

const raidConvoyStart = RaidVec(500, 1360);
const raidConvoyRoute = [
  RaidVec(250, 1320),
  RaidVec(250, 1130),
  RaidVec(330, 1040),
  RaidVec(890, 1040),
  RaidVec(890, 810),
  RaidVec(890, 560),
  RaidVec(270, 560),
  RaidVec(270, 440),
  RaidVec(270, 220),
  RaidVec(560, 220),
  raidBeacon,
];
const raidConvoyStops = [1, 4, 7, 10];

class RaidConvoy {
  RaidVec position = raidConvoyStart;
  double health = 8, immunity = 0;
  int waypoint = 0;
}

class RaidBlast {
  final RaidVec position;
  double delay = .95, life = .2;
  bool hitPlayer = false, hitConvoy = false;
  RaidBlast(this.position);
  static const radius = 72.0;
}

class RaidBeam {
  final RaidVec from, to;
  double life = .32;
  bool hitPlayer = false, hitConvoy = false;
  RaidBeam(this.from, this.to);
}

class RaidArc {
  final RaidVec from, to;
  double life = .18;
  RaidArc(this.from, this.to);
}

class RaidHazard {
  final RaidVec position;
  final double offset, radius;
  const RaidHazard(this.position, this.offset, [this.radius = 78]);
  double cycle(double elapsed) => (elapsed + offset) % 6;
  bool warning(double elapsed) => cycle(elapsed) >= 3.8 && cycle(elapsed) < 4.8;
  bool active(double elapsed) => cycle(elapsed) >= 4.8;
}

const raidSolarHazards = [
  RaidHazard(RaidVec(650, 1080), 0),
  RaidHazard(RaidVec(365, 785), 2),
  RaidHazard(RaidVec(650, 485), 4),
];

class RaidDrone {
  final int id;
  final RaidDroneKind kind;
  RaidVec position, aim = const RaidVec(0, 1);
  double hp, cooldown, windup = 0, flash = 0, arrival = .8;
  double chargeTime = 0, repairGlow = 0;
  double guardClock = 0;
  double jumpTime = 0;
  RaidVec jumpFrom = RaidVec.zero, jumpTarget = RaidVec.zero;
  RaidVec? repairTarget;
  int attack = 0;
  bool radialAttack = false;
  RaidDrone(this.id, this.kind, this.position)
    : hp = healthFor(kind),
      cooldown = .9 + (id % 3) * .35;
  double get radius => kind == RaidDroneKind.guardian ? 43 : 25;
  static double healthFor(RaidDroneKind kind) => switch (kind) {
    RaidDroneKind.guardian => 100,
    RaidDroneKind.sentry => 8,
    RaidDroneKind.interceptor => 7,
    RaidDroneKind.repairer => 6,
    RaidDroneKind.relay => 12,
    RaidDroneKind.prism => 8,
    RaidDroneKind.bomber => 8,
    RaidDroneKind.bulwark => 8,
    RaidDroneKind.boomerang => 8,
    RaidDroneKind.pulsar => 8,
    RaidDroneKind.hopper => 7,
    RaidDroneKind.scout => 5,
  };
  double get maxHp => healthFor(kind);
  List<double> get shotAngles => kind == RaidDroneKind.guardian
      ? (radialAttack
            ? List.generate(12, (i) => i * math.pi / 6)
            : [-.56, -.28, 0.0, .28, .56])
      : kind == RaidDroneKind.sentry
      ? [-.18, 0.0, .18]
      : [0.0];
}

class RaidBolt {
  RaidVec position;
  RaidVec velocity;
  final bool hostile;
  final double damage;
  int pierces;
  int ricochets;
  final hitDrones = <int>{};
  bool chainUsed = false;
  double life = 2.1;
  final RaidVec? returnOrigin;
  double returnIn;
  bool returned = false;
  RaidBolt(
    this.position,
    this.velocity,
    this.hostile,
    this.damage, {
    this.pierces = 0,
    this.ricochets = 0,
    this.returnOrigin,
    this.returnIn = .8,
  });
}

class RaidParticle {
  RaidVec position;
  final RaidVec velocity;
  final RaidEffectKind kind;
  double life;
  final double duration;
  RaidParticle(this.position, this.velocity, this.kind, this.duration)
    : life = duration;
}

class RaidEffect {
  final int id;
  final RaidEffectKind kind;
  const RaidEffect(this.id, this.kind);
}

class RayRaidWorld {
  final RaidMission mission;
  RayRaidWorld({this.mission = RaidMission.beacon});
  List<RaidBlock> get blocks => switch (mission) {
    RaidMission.beacon => raidBlocks,
    RaidMission.foundry => raidFoundryBlocks,
    RaidMission.dock => raidDockBlocks,
    RaidMission.convoy => raidConvoyBlocks,
    RaidMission.storm => raidStormBlocks,
    RaidMission.portal => raidPortalBlocks,
    RaidMission.magnet => raidMagnetBlocks,
    RaidMission.rescue => raidRescueBlocks,
    RaidMission.meteor => raidMeteorBlocks,
  };
  List<RaidHazard> get hazards =>
      mission == RaidMission.foundry ? raidSolarHazards : const [];
  bool hazardCooled(RaidHazard hazard) =>
      collected.contains(hazards.indexOf(hazard));
  bool hazardWarning(RaidHazard hazard) =>
      !hazardCooled(hazard) && hazard.warning(elapsed);
  bool hazardActive(RaidHazard hazard) =>
      !hazardCooled(hazard) && hazard.active(elapsed);
  bool lineBlocked(RaidVec from, RaidVec to, [double radius = 0]) =>
      segmentHitsCover(from, to, radius, blocks);
  RaidVec move(RaidVec from, RaidVec delta, double radius) =>
      moveWithinArena(from, delta, radius, blocks);
  RaidPhase phase = RaidPhase.ready;
  RaidVec player = raidStart, movement = RaidVec.zero, aim = RaidVec.zero;
  RaidVec facing = const RaidVec(0, -1), dashDirection = RaidVec.zero;
  final drones = <RaidDrone>[];
  final bolts = <RaidBolt>[];
  final particles = <RaidParticle>[];
  final effects = <RaidEffect>[];
  final blasts = <RaidBlast>[];
  final beams = <RaidBeam>[];
  final arcs = <RaidArc>[];
  final shockwaves = <RaidShockwave>[];
  final pulseRings = <RaidPulseRing>[];
  final meteors = <RaidMeteor>[];
  final rescuedBots = <int>{};
  int? carriedRescue;
  double meteorCountdown = 2.8, orbitCooldown = 0;
  final portalsUsed = <int>{};
  List<RaidConveyor> get conveyors =>
      mission == RaidMission.magnet ? raidConveyors : const [];
  final convoy = RaidConvoy();
  final antennaCharge = [0.0, 0.0, 0.0];
  final collected = <int>{};
  final upgrades = <RaidUpgrade, int>{for (final u in RaidUpgrade.values) u: 0};
  double health = 6, elapsed = 0, dashCooldown = 0, shieldCooldown = 0;
  double dashTime = 0, shieldTime = 0, immunity = 0, damageFlash = 0;
  double fireCooldown = 0, accumulator = 0;
  double companionCooldown = 0;
  int repairedPulses = 0, relaysDisabled = 0;
  int beamAttacks = 0, blastAttacks = 0, chainHits = 0, frostSteps = 0;
  int portalHops = 0, conveyorSteps = 0, returnAttacks = 0, returnTurns = 0;
  int reflectedBolts = 0, shockHits = 0;
  int rescuePickups = 0, meteorWarnings = 0, meteorStrikes = 0;
  int meteorDroneHits = 0, pulseAttacks = 0, jumpAttacks = 0, jumpLandings = 0;
  int ricochetBounces = 0, orbitBlocks = 0;
  bool firing = false, paused = false, guardianSpawned = false;
  bool coreUnlocked = false;
  int encounterWave = 0;
  int disabledDrones = 0,
      dashUses = 0,
      shieldUses = 0,
      _effectId = 0,
      _droneId = 0;
  int shieldCharges = 0;
  int get coreCount => collected.length;
  int get moduleCount => upgrades.values.fold(0, (a, b) => a + b);
  double get maxHealth => 6.0 + upgrades[RaidUpgrade.shield]!;
  double get dashRecharge => [4.0, 2.8, 2.0][upgrades[RaidUpgrade.dash]!];
  double get shieldRecharge => [8.0, 7.0, 6.0][upgrades[RaidUpgrade.shield]!];
  double get shotInterval => upgrades[RaidUpgrade.pulse] == 2 ? .22 : .32;
  bool get guardianAlive => drones.any((d) => d.kind == RaidDroneKind.guardian);
  bool get relayAlive =>
      drones.any((d) => d.kind == RaidDroneKind.relay && d.hp > 0);
  bool shielded(RaidDrone drone) =>
      drone.kind == RaidDroneKind.bulwark && drone.guardClock % 4 < 1.5 ||
      mission == RaidMission.dock &&
          relayAlive &&
          drone.kind != RaidDroneKind.relay;
  bool get portalReady =>
      mission != RaidMission.portal ||
      coreCount == 3 ||
      portalsUsed.contains(coreCount);
  bool get rescueReady =>
      mission != RaidMission.rescue ||
      coreCount == 3 ||
      rescuedBots.contains(coreCount);
  RaidVec rescuePosition(int i) => rescuedBots.contains(i)
      ? raidCores[i] + const RaidVec(-28, 0)
      : carriedRescue == i
      ? player + const RaidVec(24, -28)
      : raidRescueBots[i];
  RaidVec get orbitPosition => clampToArena(
    player + RaidVec(math.cos(elapsed * 2.7), math.sin(elapsed * 2.7)) * 78,
    16,
  );
  double get movementSpeed => carriedRescue == null ? 215 : 185;
  RaidVec get companionPosition => clampToArena(
    player + RaidVec(math.cos(elapsed * 2), math.sin(elapsed * 2)) * 58,
    18,
  );
  bool get escorting => mission == RaidMission.convoy;
  int get convoyStop => raidConvoyStops[coreCount];
  bool get convoyAtStop => convoy.waypoint > convoyStop;
  RaidVec get convoyNextPoint =>
      raidConvoyRoute[math.min(convoy.waypoint, convoyStop)];
  bool get antennaReady =>
      mission != RaidMission.storm ||
      coreCount == 3 ||
      antennaCharge[coreCount] >= 4;
  double get frostRadius => upgrades[RaidUpgrade.frost] == 2 ? 310 : 245;
  bool get frostActive =>
      shieldTime > 0 && shieldCharges > 0 && upgrades[RaidUpgrade.frost]! > 0;
  double enemyTimeScale(RaidVec at) =>
      frostActive &&
          player.distance(at) <= frostRadius &&
          !lineBlocked(player, at)
      ? upgrades[RaidUpgrade.frost] == 2
            ? .35
            : .55
      : 1;
  bool get canLaunch =>
      coreCount == 3 &&
      guardianSpawned &&
      !guardianAlive &&
      (!escorting || convoyAtStop);
  bool get simulating => phase == RaidPhase.playing && !paused;
  String get objective {
    if (coreCount < 3) {
      String action;
      if (relayAlive) {
        action = 'Отключи генератор щита';
      } else if (!coreUnlocked) {
        action = 'Отключи дронов';
      } else if (escorting && !convoyAtStop) {
        action = 'Сопроводи грузовика';
      } else if (!antennaReady) {
        action =
            'Связь ${(antennaCharge[coreCount] / 4 * 100).floor()}% • держись в круге';
      } else if (!portalReady) {
        action = 'Войди в голубой портал';
      } else if (!rescueReady) {
        action = carriedRescue == null
            ? 'Подбери маленького робота'
            : 'Отнеси друга к площадке';
      } else {
        action = mission == RaidMission.foundry
            ? 'Включи охлаждение'
            : 'Забери энергоблок';
      }
      return '$action • ${coreCount + 1}/3';
    }
    if (relayAlive) return 'Сначала генератор щита';
    if (guardianAlive) return 'Отключи Стража';
    if (escorting && !convoyAtStop) return 'Сопроводи грузовика к финишу';
    return mission == RaidMission.beacon
        ? 'Запусти маяк'
        : 'Включи пульт станции';
  }

  void start() {
    if (phase != RaidPhase.ready) return;
    phase = RaidPhase.playing;
    _spawnEncounter();
  }

  void _spawnEncounter() {
    final positions = switch ((coreCount, encounterWave)) {
      (0, 0) => [const RaidVec(350, 1050), const RaidVec(825, 1090)],
      (0, _) => [
        const RaidVec(130, 1050),
        const RaidVec(920, 1080),
        const RaidVec(540, 820),
      ],
      (1, 0) => [
        const RaidVec(790, 760),
        const RaidVec(1000, 660),
        const RaidVec(560, 550),
      ],
      (1, _) => [const RaidVec(610, 680), const RaidVec(960, 520)],
      (2, 0) => [
        const RaidVec(280, 300),
        const RaidVec(680, 510),
        const RaidVec(870, 270),
      ],
      _ => [
        const RaidVec(140, 220),
        const RaidVec(620, 260),
        const RaidVec(930, 540),
      ],
    };
    if (mission == RaidMission.dock && encounterWave == 0) {
      drones.add(
        RaidDrone(_droneId++, RaidDroneKind.relay, raidCores[coreCount]),
      );
    }
    for (var i = 0; i < positions.length; i++) {
      final kind =
          mission == RaidMission.rescue || mission == RaidMission.meteor
          ? (i == 0
                ? RaidDroneKind.pulsar
                : i == 1
                ? RaidDroneKind.hopper
                : RaidDroneKind.boomerang)
          : mission == RaidMission.portal || mission == RaidMission.magnet
          ? (i == 0
                ? RaidDroneKind.bulwark
                : i == 1
                ? RaidDroneKind.boomerang
                : RaidDroneKind.interceptor)
          : mission.index >= RaidMission.convoy.index
          ? (i == 0
                ? RaidDroneKind.prism
                : i == 1
                ? RaidDroneKind.bomber
                : RaidDroneKind.interceptor)
          : mission == RaidMission.beacon
          ? (coreCount > 0 && i == 0
                ? RaidDroneKind.sentry
                : RaidDroneKind.scout)
          : i == 0 && (encounterWave == 1 || coreCount > 0)
          ? RaidDroneKind.repairer
          : i.isOdd || coreCount == 0
          ? RaidDroneKind.interceptor
          : RaidDroneKind.sentry;
      drones.add(RaidDrone(_droneId++, kind, positions[i]));
    }
  }

  void setMove(RaidVec value) {
    movement = simulating ? value.limited : RaidVec.zero;
  }

  void setAim(RaidVec value, {required bool shooting}) {
    aim = simulating ? value.limited : RaidVec.zero;
    firing = simulating && shooting;
  }

  void clearInput() {
    movement = RaidVec.zero;
    aim = RaidVec.zero;
    firing = false;
  }

  void setPaused(bool value) {
    paused = value;
    accumulator = 0;
    clearInput();
  }

  bool dash() {
    if (!simulating || dashCooldown > 0 || dashTime > 0) return false;
    dashDirection = movement.length > .1 ? movement.unit : facing;
    dashTime = .19 + upgrades[RaidUpgrade.dash]! * .025;
    dashCooldown = dashRecharge;
    dashUses++;
    _effect(RaidEffectKind.dash, player, 7);
    if (upgrades[RaidUpgrade.shock]! > 0) _shock();
    return true;
  }

  void _shock() {
    final level = upgrades[RaidUpgrade.shock]!;
    final radius = level == 2 ? 180.0 : 140.0;
    if (shockwaves.length < 8) shockwaves.add(RaidShockwave(player, radius));
    for (final drone in drones) {
      if (drone.arrival > 0 ||
          player.distance(drone.position) > radius + drone.radius ||
          lineBlocked(player, drone.position)) {
        continue;
      }
      if (_hitDrone(drone, level == 2 ? 3 : 2)) {
        shockHits++;
        if (drone.kind != RaidDroneKind.guardian &&
            drone.kind != RaidDroneKind.relay &&
            drone.jumpTime == 0) {
          drone.position = move(
            drone.position,
            (drone.position - player).unit * 65,
            math.max(32, drone.radius),
          );
        }
      }
    }
  }

  bool shield() {
    if (!simulating || shieldCooldown > 0 || shieldTime > 0) return false;
    shieldTime = 2.3 + upgrades[RaidUpgrade.shield]! * .8;
    shieldCharges = 2 + upgrades[RaidUpgrade.shield]!;
    shieldCooldown = shieldRecharge;
    shieldUses++;
    _effect(RaidEffectKind.shield, player, 8);
    return true;
  }

  bool selectUpgrade(RaidUpgrade upgrade) {
    if (phase != RaidPhase.upgrade || upgrades[upgrade]! >= 2) return false;
    upgrades[upgrade] = upgrades[upgrade]! + 1;
    health = math.min(maxHealth, health + 1);
    phase = RaidPhase.playing;
    accumulator = 0;
    clearInput();
    if (coreCount == 3 && !guardianSpawned) {
      guardianSpawned = true;
      drones.add(
        RaidDrone(_droneId++, RaidDroneKind.guardian, const RaidVec(560, 265)),
      );
      if (mission == RaidMission.dock) {
        drones.add(
          RaidDrone(_droneId++, RaidDroneKind.relay, const RaidVec(850, 180)),
        );
      }
    } else if (coreCount < 3) {
      encounterWave = 0;
      coreUnlocked = false;
      _spawnEncounter();
    }
    return true;
  }

  /// Long or invalid frame gaps never fast-forward combat after a suspension.
  void advance(double seconds) {
    if (!simulating || !seconds.isFinite || seconds <= 0) {
      accumulator = 0;
      return;
    }
    accumulator = math.min(accumulator + math.min(seconds, .1), .1);
    for (var i = 0; accumulator >= 1 / 120 && i < 12 && simulating; i++) {
      accumulator -= 1 / 120;
      _step(1 / 120);
    }
  }

  void _step(double dt) {
    elapsed += dt;
    dashCooldown = math.max(0, dashCooldown - dt);
    shieldCooldown = math.max(0, shieldCooldown - dt);
    shieldTime = math.max(0, shieldTime - dt);
    immunity = math.max(0, immunity - dt);
    damageFlash = math.max(0, damageFlash - dt);
    fireCooldown = math.max(0, fireCooldown - dt);
    companionCooldown = math.max(0, companionCooldown - dt);
    orbitCooldown = math.max(0, orbitCooldown - dt);
    convoy.immunity = math.max(0, convoy.immunity - dt);
    final direction = dashTime > 0 ? dashDirection : movement;
    final speed = dashTime > 0 ? 870.0 : movementSpeed;
    player = move(player, direction * (speed * dt), 22);
    for (final belt in conveyors) {
      if (belt.area.contains(player)) {
        player = move(player, belt.direction * (85 * dt), 22);
        conveyorSteps++;
      }
    }
    if (!portalReady && player.distance(raidPortals[coreCount].entry) < 42) {
      final portal = raidPortals[coreCount];
      portalsUsed.add(coreCount);
      portalHops++;
      player = portal.exit;
      immunity = math.max(immunity, .65);
      _effect(RaidEffectKind.core, player, 12);
    }
    if (!firing && direction.length > .12) facing = direction.unit;
    if (firing && aim.length > .18) facing = aim.unit;
    dashTime = math.max(0, dashTime - dt);
    if (firing && fireCooldown == 0) _shoot();
    if (upgrades[RaidUpgrade.companion]! > 0 && companionCooldown == 0) {
      _companionShot();
    }
    _updateConvoy(dt);
    for (final drone in drones) {
      final scale = enemyTimeScale(drone.position);
      if (scale < 1) frostSteps++;
      _updateDrone(drone, dt * scale);
    }
    _updateBolts(dt);
    _updateAttacks(dt);
    _updateMeteors(dt);
    if (phase == RaidPhase.playing) {
      for (final hazard in hazards) {
        if (hazardActive(hazard) &&
            player.distance(hazard.position) < hazard.radius + 18) {
          _damage();
        }
      }
    }
    for (final p in particles) {
      p.position = p.position + p.velocity * dt;
      p.life -= dt;
    }
    particles.removeWhere((p) => p.life <= 0);
    drones.removeWhere((d) => d.hp <= 0);
    if (phase != RaidPhase.playing) return;
    if (!rescueReady) {
      final i = coreCount;
      if (carriedRescue == null &&
          player.distance(raidRescueBots[i]) < 58 &&
          !lineBlocked(player, raidRescueBots[i], 12)) {
        carriedRescue = i;
        rescuePickups++;
        _effect(RaidEffectKind.core, player, 8);
      }
      if (carriedRescue == i && player.distance(raidCores[i]) < 65) {
        rescuedBots.add(i);
        carriedRescue = null;
        _effect(RaidEffectKind.core, raidCores[i], 14);
      }
    }
    if (mission == RaidMission.storm &&
        coreCount < 3 &&
        player.distance(raidCores[coreCount]) < 86) {
      antennaCharge[coreCount] = math.min(4, antennaCharge[coreCount] + dt);
    }
    if (coreCount < 3 && drones.isEmpty && !coreUnlocked) {
      if (encounterWave == 0) {
        encounterWave = 1;
        _spawnEncounter();
      } else {
        coreUnlocked = true;
        _effect(RaidEffectKind.core, raidCores[coreCount], 12);
      }
    }
    for (var i = 0; i < raidCores.length; i++) {
      if (i == coreCount &&
          coreUnlocked &&
          antennaReady &&
          portalReady &&
          rescueReady &&
          (!escorting || convoyAtStop) &&
          player.distance(raidCores[i]) < 46) {
        collected.add(i);
        health = maxHealth;
        if (escorting) convoy.health = 8;
        bolts.removeWhere((b) => b.hostile);
        beams.clear();
        blasts.clear();
        pulseRings.clear();
        meteors.clear();
        immunity = .8;
        _effect(RaidEffectKind.core, raidCores[i], 16);
        phase = RaidPhase.upgrade;
        clearInput();
        accumulator = 0;
        return;
      }
    }
    if (canLaunch && player.distance(raidBeacon) < 75) {
      phase = RaidPhase.won;
      clearInput();
      _effect(RaidEffectKind.win, player, 28);
    }
  }

  void _updateConvoy(double dt) {
    if (!escorting ||
        convoy.health <= 0 ||
        convoyAtStop ||
        player.distance(convoy.position) > 210) {
      return;
    }
    final target = convoyNextPoint;
    final offset = target - convoy.position;
    final distance = math.min(offset.length, 115 * dt);
    convoy.position = move(convoy.position, offset.unit * distance, 31);
    if (convoy.position.distance(target) < 2) convoy.waypoint++;
  }

  RaidVec rayEnd(RaidVec from, RaidVec direction, [double distance = 570]) =>
      raidRayEnd(from, direction, distance, blocks);

  void _updateAttacks(double dt) {
    for (final ring in pulseRings) {
      final before = ring.radius;
      ring.radius += RaidPulseRing.speed * dt;
      final distance = player.distance(ring.position);
      if (!ring.hitPlayer &&
          distance >= before - 22 &&
          distance <= ring.radius + 22) {
        ring.hitPlayer = true;
        _damage();
      }
    }
    pulseRings.removeWhere((r) => r.radius > RaidPulseRing.limit);
    for (final beam in beams) {
      if (!beam.hitPlayer && segmentDistance(player, beam.from, beam.to) < 27) {
        beam.hitPlayer = true;
        _damage();
      }
      if (escorting &&
          !beam.hitConvoy &&
          segmentDistance(convoy.position, beam.from, beam.to) < 34) {
        beam.hitConvoy = true;
        _damageConvoy();
      }
      beam.life -= dt;
    }
    for (final blast in blasts) {
      if (blast.delay > 0) {
        blast.delay = math.max(0, blast.delay - dt);
        continue;
      }
      if (!blast.hitPlayer &&
          player.distance(blast.position) < RaidBlast.radius + 22) {
        blast.hitPlayer = true;
        _damage();
      }
      if (escorting &&
          !blast.hitConvoy &&
          convoy.position.distance(blast.position) < RaidBlast.radius + 31) {
        blast.hitConvoy = true;
        _damageConvoy();
      }
      blast.life -= dt;
    }
    for (final arc in arcs) {
      arc.life -= dt;
    }
    for (final wave in shockwaves) {
      wave.life -= dt;
    }
    shockwaves.removeWhere((w) => w.life <= 0);
    beams.removeWhere((b) => b.life <= 0);
    blasts.removeWhere((b) => b.life <= 0);
    arcs.removeWhere((a) => a.life <= 0);
  }

  void _updateMeteors(double dt) {
    if (mission != RaidMission.meteor || phase != RaidPhase.playing) return;
    meteorCountdown -= dt;
    if (meteorCountdown <= 0) {
      if (meteors.length < 4) {
        meteors.add(RaidMeteor(player));
        meteorWarnings++;
      }
      meteorCountdown = 3.2 + meteorWarnings % 3 * .2;
    }
    for (final meteor in meteors) {
      meteor.delay = math.max(0, meteor.delay - dt);
      if (meteor.delay > 0) continue;
      if (!meteor.impacted) {
        meteor.impacted = true;
        meteorStrikes++;
        if (player.distance(meteor.position) < RaidMeteor.radius + 22) {
          _damage();
        }
        for (final drone in drones) {
          if (drone.hp > 0 &&
              drone.arrival == 0 &&
              drone.position.distance(meteor.position) <
                  RaidMeteor.radius + drone.radius &&
              _hitDrone(drone, 3)) {
            meteorDroneHits++;
          }
        }
        _effect(RaidEffectKind.hit, meteor.position, 8);
      }
      meteor.life -= dt;
    }
    meteors.removeWhere((m) => m.life <= 0);
  }

  void _shoot() {
    RaidVec direction;
    if (aim.length > .18) {
      direction = aim.unit;
    } else {
      final target = _target(player, 440);
      direction = target == null ? facing : (target.position - player).unit;
    }
    facing = direction;
    final doubleShot = upgrades[RaidUpgrade.pulse]! > 0;
    for (final angle in doubleShot ? [-.075, .075] : [0.0]) {
      if (bolts.length < 64) {
        final v = direction.rotated(angle);
        bolts.add(
          RaidBolt(
            player + v * (upgrades[RaidUpgrade.ricochet]! > 0 ? 18 : 28),
            v * 620,
            false,
            1,
            pierces: upgrades[RaidUpgrade.pierce]!,
            ricochets: upgrades[RaidUpgrade.ricochet]!,
          ),
        );
      }
    }
    fireCooldown = shotInterval;
    _effect(RaidEffectKind.shot, player + direction * 30, 1);
  }

  RaidDrone? _target(RaidVec from, double range) {
    RaidDrone? target;
    for (final d in drones) {
      final distance = from.distance(d.position);
      if (d.hp > 0 &&
          d.arrival == 0 &&
          !shielded(d) &&
          distance < range &&
          !lineBlocked(from, d.position)) {
        range = distance;
        target = d;
      }
    }
    return target;
  }

  void _companionShot() {
    // The companion never fires through cover or from inside a solid crate.
    final from = companionPosition;
    if (blocks.any((b) => b.contains(from, 5)) || lineBlocked(player, from)) {
      return;
    }
    final target = _target(from, 360);
    if (target == null || bolts.length >= 64) return;
    final direction = (target.position - from).unit;
    bolts.add(RaidBolt(from + direction * 12, direction * 590, false, 1));
    companionCooldown = upgrades[RaidUpgrade.companion] == 2 ? .42 : .7;
    _effect(RaidEffectKind.shot, from, 1);
  }

  void _updateDrone(RaidDrone d, double dt) {
    if (d.hp <= 0) return;
    d.guardClock += dt;
    if (d.arrival > 0) {
      d.arrival = math.max(0, d.arrival - dt);
      return;
    }
    if (d.kind == RaidDroneKind.relay) {
      d.flash = math.max(0, d.flash - dt);
      return;
    }
    if (d.kind == RaidDroneKind.hopper && d.jumpTime > 0) {
      d.jumpTime = math.max(0, d.jumpTime - dt);
      d.position =
          d.jumpFrom + (d.jumpTarget - d.jumpFrom) * (1 - d.jumpTime / .65);
      if (d.jumpTime == 0) {
        jumpLandings++;
        if (blasts.length < 16) {
          blasts.add(RaidBlast(d.jumpTarget)..delay = 0);
        }
      }
      return;
    }
    if (player.distance(d.position) < d.radius + 20) _damage();
    d.flash = math.max(0, d.flash - dt);
    final toward = player - d.position;
    final distance = toward.length;
    if (d.kind == RaidDroneKind.repairer) {
      _updateRepairer(d, dt, toward);
      return;
    }
    if (d.kind == RaidDroneKind.interceptor && d.chargeTime > 0) {
      d.chargeTime = math.max(0, d.chargeTime - dt);
      final before = d.position;
      d.position = move(d.position, d.aim * (590 * dt), d.radius);
      if (segmentDistance(player, before, d.position) < d.radius + 20) {
        _damage();
      }
      if (before.distance(d.position) < 590 * dt * .45) d.chargeTime = 0;
      return;
    }
    if (d.windup > 0) {
      d.windup -= dt;
      if (d.windup <= 0) {
        if (d.kind == RaidDroneKind.pulsar) {
          if (pulseRings.length < 8) {
            pulseRings.add(RaidPulseRing(d.position));
            pulseAttacks++;
          }
          d.cooldown = 3.1;
          d.attack++;
          return;
        }
        if (d.kind == RaidDroneKind.hopper) {
          d.jumpFrom = d.position;
          d.jumpTime = .65;
          d.cooldown = 3.0;
          d.attack++;
          jumpAttacks++;
          return;
        }
        if (d.kind == RaidDroneKind.interceptor) {
          d.chargeTime = .44;
          d.cooldown = 2.3;
          d.attack++;
          return;
        }
        if (d.kind == RaidDroneKind.prism || d.kind == RaidDroneKind.bomber) {
          if (d.kind == RaidDroneKind.prism && beams.length < 8) {
            beams.add(RaidBeam(d.position, rayEnd(d.position, d.aim)));
            beamAttacks++;
          } else if (d.kind == RaidDroneKind.bomber && blasts.length < 16) {
            blasts.add(RaidBlast(player));
            blastAttacks++;
          }
          d.attack++;
          d.cooldown = d.kind == RaidDroneKind.prism ? 2.4 : 2.5;
          return;
        }
        final guardian = d.kind == RaidDroneKind.guardian;
        final boomerang = d.kind == RaidDroneKind.boomerang;
        final spread = d.shotAngles;
        for (final a in spread) {
          if (bolts.length < 64) {
            final direction = d.aim.rotated(a);
            final bolt = RaidBolt(
              d.position + direction * (d.radius + 9),
              direction *
                  (boomerang
                      ? 245
                      : guardian
                      ? 205
                      : 175),
              true,
              1,
              returnOrigin: boomerang ? d.position : null,
            );
            if (boomerang) {
              bolt.life = 2.7;
              returnAttacks++;
            }
            bolts.add(bolt);
          }
        }
        d.attack++;
        d.cooldown = guardian
            ? 1.45
            : d.kind == RaidDroneKind.sentry
            ? 2.1
            : 1.8;
      }
    } else {
      d.cooldown -= dt;
      // Keep targets out of solid cover so every drone remains reachable.
      final stopDistance = d.kind == RaidDroneKind.guardian ? 260 : 235;
      if (distance > stopDistance) {
        final speed = d.kind == RaidDroneKind.guardian ? 65.0 : 92.0;
        _moveDrone(d, toward.unit * (speed * dt));
      } else if (distance < 110) {
        _moveDrone(d, toward.unit * (-48 * dt));
      } else {
        final strafe = RaidVec(-toward.unit.y, toward.unit.x);
        _moveDrone(d, strafe * (math.sin(elapsed + d.id) * 28 * dt));
      }
      if (d.cooldown <= 0 &&
          distance < 540 &&
          !lineBlocked(d.position, player)) {
        d.radialAttack =
            d.kind == RaidDroneKind.guardian &&
            d.attack.isOdd &&
            d.hp < d.maxHp / 2;
        d.aim = toward.unit;
        if (d.kind == RaidDroneKind.hopper) {
          d.jumpTarget = move(
            d.position,
            toward.unit * math.min(distance, 260),
            32,
          );
        }
        d.windup = d.kind == RaidDroneKind.guardian
            ? .85
            : d.kind == RaidDroneKind.pulsar || d.kind == RaidDroneKind.hopper
            ? .9
            : d.kind == RaidDroneKind.prism
            ? 1.0
            : d.kind == RaidDroneKind.interceptor
            ? .75
            : .65;
      }
    }
  }

  void _updateRepairer(RaidDrone d, double dt, RaidVec toward) {
    d.repairGlow = math.max(0, d.repairGlow - dt);
    if (d.repairGlow == 0) d.repairTarget = null;
    d.cooldown -= dt;
    if (toward.length < 160) {
      _moveDrone(d, toward.unit * (-65 * dt));
    } else if (toward.length > 330) {
      _moveDrone(d, toward.unit * (80 * dt));
    }
    if (d.cooldown > 0) return;
    RaidDrone? target;
    for (final other in drones) {
      if (other.id == d.id ||
          other.hp <= 0 ||
          other.arrival > 0 ||
          other.hp >= other.maxHp ||
          other.kind == RaidDroneKind.relay ||
          other.kind == RaidDroneKind.repairer) {
        continue;
      }
      if (d.position.distance(other.position) < 300 &&
          !lineBlocked(d.position, other.position)) {
        if (target == null ||
            other.hp / other.maxHp < target.hp / target.maxHp) {
          target = other;
        }
      }
    }
    if (target == null) return;
    target.hp = math.min(target.maxHp, target.hp + 2);
    d.repairTarget = target.position;
    d.repairGlow = .5;
    d.cooldown = 2.6;
    repairedPulses++;
  }

  void _moveDrone(RaidDrone d, RaidVec delta) {
    final radius = math.max(32.0, d.radius);
    final next = move(d.position, delta, radius);
    if (next.distance(d.position) < delta.length * .5) {
      final side = RaidVec(-delta.y, delta.x) * (d.id.isEven ? 1 : -1);
      d.position = move(d.position, side, radius);
    } else {
      d.position = next;
    }
  }

  void _updateBolts(double dt) {
    final reflected = <RaidBolt>[];
    for (final bolt in bolts) {
      if (bolt.life <= 0) continue;
      final scale = bolt.hostile ? enemyTimeScale(bolt.position) : 1.0;
      if (bolt.returnOrigin != null && !bolt.returned) {
        bolt.returnIn -= dt * scale;
        if (bolt.returnIn <= 0) {
          bolt.returned = true;
          bolt.velocity = (bolt.returnOrigin! - bolt.position).unit * 245;
          returnTurns++;
        }
      }
      final next = bolt.position + bolt.velocity * (dt * scale);
      bolt.life -= dt * scale;
      if (next.x < 20 ||
          next.x > raidWorldWidth - 20 ||
          next.y < 20 ||
          next.y > raidWorldHeight - 20 ||
          lineBlocked(bolt.position, next, 4)) {
        if (!bolt.hostile &&
            bolt.ricochets > 0 &&
            bolt.life > 0 &&
            bolt.position.finite &&
            next.finite) {
          final collision = raidBoltSurface(bolt.position, next, blocks);
          if (collision != null && collision.normal.length > .1) {
            bolt.position =
                bolt.position +
                (next - bolt.position) * collision.fraction +
                collision.normal * .06;
            bolt.velocity = RaidVec(
              collision.normal.x == 0 ? bolt.velocity.x : -bolt.velocity.x,
              collision.normal.y == 0 ? bolt.velocity.y : -bolt.velocity.y,
            );
            bolt.ricochets--;
            ricochetBounces++;
            _effect(RaidEffectKind.shot, bolt.position, 2);
            continue;
          }
        }
        bolt.life = 0;
      } else if (bolt.hostile) {
        if (upgrades[RaidUpgrade.orbit]! > 0 &&
            orbitCooldown == 0 &&
            segmentDistance(player, bolt.position, next) <
                (upgrades[RaidUpgrade.orbit] == 2 ? 110 : 90)) {
          bolt.life = 0;
          orbitCooldown = upgrades[RaidUpgrade.orbit] == 2 ? 1.8 : 3;
          orbitBlocks++;
          if (arcs.length < 12) arcs.add(RaidArc(orbitPosition, next));
          _effect(RaidEffectKind.shield, next, 4);
          continue;
        }
        final radius = shieldTime > 0 && shieldCharges > 0 ? 50 : 26;
        if (segmentDistance(player, bolt.position, next) < radius) {
          bolt.life = 0;
          final level = upgrades[RaidUpgrade.reflect]!;
          if (level > 0 &&
              shieldTime > 0 &&
              shieldCharges > 0 &&
              immunity == 0 &&
              dashTime == 0 &&
              bolts.length + reflected.length < 64) {
            final direction = bolt.velocity.unit * -1;
            final origin = player + direction * 55;
            if (!lineBlocked(player, origin, 4)) {
              reflected.add(
                RaidBolt(
                  origin,
                  direction * 620,
                  false,
                  level == 2 ? 3 : 2,
                  pierces: level == 2 ? 1 : 0,
                ),
              );
              reflectedBolts++;
            }
          }
          _damage();
        } else if (escorting &&
            segmentDistance(convoy.position, bolt.position, next) < 35) {
          bolt.life = 0;
          _damageConvoy();
        }
      } else {
        for (final d in drones) {
          if (d.hp > 0 &&
              !bolt.hitDrones.contains(d.id) &&
              d.arrival == 0 &&
              segmentDistance(d.position, bolt.position, next) < d.radius + 5) {
            bolt.hitDrones.add(d.id);
            final hit = _hitDrone(d, bolt.damage);
            d.flash = .12;
            if (hit && !bolt.chainUsed && upgrades[RaidUpgrade.chain]! > 0) {
              _chain(d, bolt);
            }
            if (bolt.pierces > 0 && hit) {
              bolt.pierces--;
            } else {
              bolt.life = 0;
            }
            break;
          }
        }
      }
      bolt.position = next;
    }
    bolts.removeWhere((b) => b.life <= 0);
    bolts.addAll(reflected);
  }

  bool _hitDrone(RaidDrone drone, double damage) {
    if (drone.hp <= 0 || shielded(drone)) return false;
    drone.hp -= damage;
    drone.flash = .12;
    if (drone.hp <= 0) {
      if (drone.kind == RaidDroneKind.relay) {
        relaysDisabled++;
      } else {
        disabledDrones++;
      }
      _effect(RaidEffectKind.drone, drone.position, 10);
    }
    return true;
  }

  void _chain(RaidDrone from, RaidBolt bolt) {
    bolt.chainUsed = true;
    final level = upgrades[RaidUpgrade.chain]!;
    var origin = from.position;
    var jumps = 0;
    for (var hop = 0; hop < level && arcs.length < 12; hop++) {
      RaidDrone? target;
      var distance = level == 2 ? 185.0 : 135.0;
      for (final drone in drones) {
        final range = origin.distance(drone.position);
        if (drone.hp > 0 &&
            drone.arrival == 0 &&
            !bolt.hitDrones.contains(drone.id) &&
            !shielded(drone) &&
            range < distance &&
            !lineBlocked(origin, drone.position)) {
          target = drone;
          distance = range;
        }
      }
      if (target == null) break;
      bolt.hitDrones.add(target.id);
      if (_hitDrone(target, 1)) {
        arcs.add(RaidArc(origin, target.position));
        chainHits++;
        jumps++;
      }
      origin = target.position;
    }
    // An isolated opponent still benefits from the module: unused chain
    // energy strengthens this one pulse, once, without a recursive bounce.
    if (jumps == 0 && from.hp > 0) _hitDrone(from, level * .5);
  }

  void _damageConvoy() {
    if (!escorting ||
        convoy.immunity > 0 ||
        convoy.health <= 0 ||
        phase != RaidPhase.playing) {
      return;
    }
    convoy.immunity = .85;
    if (player.distance(convoy.position) <= 210 &&
        shieldTime > 0 &&
        shieldCharges > 0) {
      shieldCharges--;
      if (shieldCharges == 0) shieldTime = 0;
      _effect(RaidEffectKind.shield, convoy.position, 4);
      return;
    }
    convoy.health = math.max(0, convoy.health - 1);
    _effect(RaidEffectKind.hit, convoy.position, 5);
    if (convoy.health == 0) {
      phase = RaidPhase.lost;
      clearInput();
    }
  }

  void _damage() {
    if (immunity > 0 || dashTime > 0 || phase != RaidPhase.playing) return;
    if (shieldTime > 0 && shieldCharges > 0) {
      shieldCharges--;
      if (shieldCharges == 0) shieldTime = 0;
      _effect(RaidEffectKind.shield, player, 4);
      immunity = .18;
      return;
    }
    health = math.max(0, health - 1);
    immunity = .85;
    damageFlash = .22;
    _effect(RaidEffectKind.hit, player, 7);
    if (health == 0) {
      phase = RaidPhase.lost;
      clearInput();
    }
  }

  void _effect(RaidEffectKind kind, RaidVec p, int count) {
    effects.add(RaidEffect(_effectId++, kind));
    if (effects.length > 24) effects.removeAt(0);
    for (var i = 0; i < count && particles.length < 96; i++) {
      final a = i * math.pi * 2 / count + elapsed;
      final speed = kind == RaidEffectKind.shot ? 35.0 : 75.0 + i % 3 * 24;
      particles.add(
        RaidParticle(
          p,
          RaidVec(math.cos(a), math.sin(a)) * speed,
          kind,
          kind == RaidEffectKind.win ? 1.5 : .38 + i % 3 * .08,
        ),
      );
    }
  }
}

class RaidSurfaceHit {
  final double fraction;
  final RaidVec normal;
  const RaidSurfaceHit(this.fraction, this.normal);
}

/// Earliest solid surface, including arena walls. A pulse never skips cover.
RaidSurfaceHit? raidBoltSurface(
  RaidVec from,
  RaidVec to,
  List<RaidBlock> blocks,
) {
  if (!from.finite ||
      !to.finite ||
      from.x < 20 ||
      from.x > raidWorldWidth - 20 ||
      from.y < 20 ||
      from.y > raidWorldHeight - 20) {
    return null;
  }
  final delta = to - from;
  RaidSurfaceHit? first;
  void consider(double fraction, RaidVec normal) {
    if (!fraction.isFinite || fraction < 0 || fraction > 1) return;
    if (first == null || fraction < first!.fraction - .000001) {
      first = RaidSurfaceHit(fraction, normal);
    } else if ((fraction - first!.fraction).abs() < .000001) {
      first = RaidSurfaceHit(fraction, (first!.normal + normal).unit);
    }
  }

  final fraction = _firstCoverFraction(from, to, 4, blocks);
  if (fraction != null) {
    final hit = from + delta * fraction;
    var normal = RaidVec.zero;
    for (final block in blocks) {
      if (!block.contains(hit, 4.001)) continue;
      var x = 0.0, y = 0.0;
      if (delta.x > 0 && (hit.x - (block.x - 4)).abs() < .001) x = -1;
      if (delta.x < 0 && (hit.x - (block.x + block.width + 4)).abs() < .001) {
        x = 1;
      }
      if (delta.y > 0 && (hit.y - (block.y - 4)).abs() < .001) y = -1;
      if (delta.y < 0 && (hit.y - (block.y + block.height + 4)).abs() < .001) {
        y = 1;
      }
      normal = normal + RaidVec(x, y);
    }
    consider(fraction, normal.unit);
  }
  if (to.x < 20 && delta.x < 0) {
    consider((20 - from.x) / delta.x, const RaidVec(1, 0));
  }
  if (to.x > raidWorldWidth - 20 && delta.x > 0) {
    consider((raidWorldWidth - 20 - from.x) / delta.x, const RaidVec(-1, 0));
  }
  if (to.y < 20 && delta.y < 0) {
    consider((20 - from.y) / delta.y, const RaidVec(0, 1));
  }
  if (to.y > raidWorldHeight - 20 && delta.y > 0) {
    consider((raidWorldHeight - 20 - from.y) / delta.y, const RaidVec(0, -1));
  }
  return first;
}

RaidVec clampToArena(RaidVec p, double radius) => RaidVec(
  p.x.clamp(35 + radius, raidWorldWidth - 35 - radius).toDouble(),
  p.y.clamp(35 + radius, raidWorldHeight - 35 - radius).toDouble(),
);

RaidVec moveWithinArena(
  RaidVec from,
  RaidVec delta,
  double radius, [
  List<RaidBlock> blocks = raidBlocks,
]) {
  if (!from.finite || !delta.finite) return from.finite ? from : raidStart;
  var result = clampToArena(RaidVec(from.x + delta.x, from.y), radius);
  if (blocks.any((b) => b.contains(result, radius))) result = from;
  final vertical = clampToArena(RaidVec(result.x, result.y + delta.y), radius);
  return blocks.any((b) => b.contains(vertical, radius)) ? result : vertical;
}

double segmentDistance(RaidVec p, RaidVec from, RaidVec to) {
  final delta = to - from;
  final square = delta.x * delta.x + delta.y * delta.y;
  if (square < .000001) return p.distance(from);
  final t = (((p.x - from.x) * delta.x + (p.y - from.y) * delta.y) / square)
      .clamp(0.0, 1.0);
  return p.distance(from + delta * t);
}

bool segmentHitsCover(
  RaidVec from,
  RaidVec to, [
  double radius = 0,
  List<RaidBlock> blocks = raidBlocks,
]) => _firstCoverFraction(from, to, radius, blocks) != null;

double? _firstCoverFraction(
  RaidVec from,
  RaidVec to,
  double radius,
  List<RaidBlock> blocks,
) {
  double? first;
  for (final block in blocks) {
    // Slab intersection avoids thin-wall tunnelling even for fast projectiles.
    var low = 0.0, high = 1.0;
    final delta = to - from;
    var intersects = true;
    for (final axis in [
      (from.x, delta.x, block.x - radius, block.x + block.width + radius),
      (from.y, delta.y, block.y - radius, block.y + block.height + radius),
    ]) {
      if (axis.$2.abs() < .000001) {
        if (axis.$1 < axis.$3 || axis.$1 > axis.$4) {
          intersects = false;
          break;
        }
      } else {
        final a = (axis.$3 - axis.$1) / axis.$2,
            b = (axis.$4 - axis.$1) / axis.$2;
        low = math.max(low, math.min(a, b));
        high = math.min(high, math.max(a, b));
        if (low > high) {
          intersects = false;
          break;
        }
      }
    }
    if (intersects && (first == null || low < first)) first = low;
  }
  return first;
}

RaidVec raidRayEnd(
  RaidVec from,
  RaidVec direction,
  double length,
  List<RaidBlock> blocks,
) {
  if (!from.finite || !direction.finite || !length.isFinite || length <= 0) {
    return from.finite ? from : raidStart;
  }
  final unit = direction.unit;
  var distance = length;
  for (final axis in [
    (from.x, unit.x, raidWorldWidth),
    (from.y, unit.y, raidWorldHeight),
  ]) {
    if (axis.$2 > .000001) {
      distance = math.min(distance, (axis.$3 - 35 - axis.$1) / axis.$2);
    }
    if (axis.$2 < -.000001) {
      distance = math.min(distance, (35 - axis.$1) / axis.$2);
    }
  }
  distance = math.max(0, distance);
  final to = from + unit * distance;
  final fraction = _firstCoverFraction(from, to, 0, blocks);
  return from + unit * (distance * (fraction ?? 1));
}
