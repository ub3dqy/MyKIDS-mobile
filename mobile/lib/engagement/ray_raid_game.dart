import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'ray_raid_audio.dart';
import 'ray_raid_controls.dart';
import 'ray_raid_model.dart';
import 'ray_raid_painter.dart';

class RayRaidGame extends StatefulWidget {
  final ValueGetter<bool> canPlay;
  final VoidCallback onExit;
  final RayRaidWorld? initialWorld;
  final RaidSound? sound;
  final Future<RayRaidArt> Function()? loadArt;
  const RayRaidGame({
    super.key,
    required this.canPlay,
    required this.onExit,
    this.initialWorld,
    this.sound,
    this.loadArt,
  });
  @override
  State<RayRaidGame> createState() => _RayRaidGameState();
}

class _RayRaidGameState extends State<RayRaidGame>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late RayRaidWorld world;
  late final Ticker ticker;
  late final RaidSound sound;
  final frames = ValueNotifier<int>(0);
  final focus = FocusNode();
  RayRaidArt? art;
  Object? loadFailure;
  Duration? lastFrame;
  double hudElapsed = 0;
  int generation = 0, lastEffect = -1, loadEpoch = 0;
  bool resumed = true,
      soundEnabled = true,
      exitQuestion = false,
      calmEffects = false;
  Timer? accessibleMove, accessibleFire;
  final heldKeys = <LogicalKeyboardKey>{};
  bool get permitted => mounted && resumed && widget.canPlay();
  bool get playing => permitted && world.simulating && !exitQuestion;
  bool current(int expected) => mounted && expected == generation && permitted;

  @override
  void initState() {
    super.initState();
    world = widget.initialWorld ?? RayRaidWorld();
    sound =
        widget.sound ??
        RayRaidSound(
          () => permitted && soundEnabled && !world.paused && !exitQuestion,
        );
    WidgetsBinding.instance.addObserver(this);
    ticker = createTicker(tick);
    unawaited(load());
  }

  Future<void> load() async {
    final epoch = ++loadEpoch;
    try {
      final loaded = await (widget.loadArt ?? RayRaidArt.load)();
      if (!mounted || epoch != loadEpoch) {
        loaded.dispose();
        return;
      }
      setState(() {
        art?.dispose();
        art = loaded;
        loadFailure = null;
      });
    } catch (error) {
      if (mounted && epoch == loadEpoch) setState(() => loadFailure = error);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    calmEffects = MediaQuery.of(context).disableAnimations;
    if (!widget.canPlay()) suspend();
  }

  @override
  void didUpdateWidget(RayRaidGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.canPlay()) suspend();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    if (!resumed) suspend();
    if (mounted) setState(() {});
  }

  void clearControls() {
    generation++;
    lastFrame = null;
    heldKeys.clear();
    world.clearInput();
    accessibleMove?.cancel();
    accessibleFire?.cancel();
  }

  void suspend() {
    if (!mounted) return;
    if (world.phase == RaidPhase.playing && !world.paused) {
      world.setPaused(true);
    }
    if (ticker.isActive) ticker.stop();
    clearControls();
    sound.silence();
  }

  void tick(Duration timestamp) {
    if (!permitted || !TickerMode.valuesOf(context).enabled) {
      if (world.simulating) {
        suspend();
        setState(() {});
      }
      lastFrame = null;
      return;
    }
    final previous = lastFrame;
    lastFrame = timestamp;
    if (previous == null || art == null || !playing) return;
    final dt = (timestamp - previous).inMicroseconds / 1000000;
    final phase = world.phase;
    world.advance(dt);
    for (final effect in world.effects) {
      if (effect.id <= lastEffect) continue;
      lastEffect = effect.id;
      if (soundEnabled) sound.play(effect.kind);
    }
    frames.value++;
    hudElapsed += dt;
    if (phase != world.phase) {
      if (!world.simulating && ticker.isActive) ticker.stop();
      clearControls();
      setState(() {});
    } else if (hudElapsed >= .1) {
      hudElapsed = 0;
      setState(() {});
    }
  }

  void pause({bool exit = false}) {
    if (!permitted) return;
    setState(() {
      suspend();
      exitQuestion = exit;
    });
  }

  void resume(int expected) {
    if (!current(expected)) return;
    setState(() {
      exitQuestion = false;
      clearControls();
      world.setPaused(false);
    });
    if (world.simulating && permitted && !ticker.isActive) ticker.start();
    focus.requestFocus();
  }

  void begin(int expected, {bool replay = false}) {
    if (!current(expected) || art == null) return;
    if (!replay && world.phase != RaidPhase.ready) return;
    if (replay &&
        world.phase != RaidPhase.won &&
        world.phase != RaidPhase.lost) {
      return;
    }
    setState(() {
      if (replay) world = RayRaidWorld(mission: world.mission);
      clearControls();
      lastEffect = -1;
      exitQuestion = false;
      world.start();
    });
    if (world.simulating && permitted && !ticker.isActive) ticker.start();
    focus.requestFocus();
  }

  void exit(int expected) {
    if (!current(expected)) return;
    suspend();
    widget.onExit();
  }

  void selectMission(int expected, RaidMission mission) {
    if (!current(expected) ||
        !{
          RaidPhase.ready,
          RaidPhase.won,
          RaidPhase.lost,
        }.contains(world.phase)) {
      return;
    }
    if (world.phase == RaidPhase.ready && mission == world.mission) return;
    setState(() {
      suspend();
      world = RayRaidWorld(mission: mission);
      lastEffect = -1;
      exitQuestion = false;
    });
  }

  void choose(int expected, RaidUpgrade upgrade) {
    if (!current(expected) || world.phase != RaidPhase.upgrade) return;
    if (world.selectUpgrade(upgrade)) setState(clearControls);
    if (world.simulating && permitted && !ticker.isActive) ticker.start();
    focus.requestFocus();
  }

  void semanticInput(RaidVec direction, bool firing) {
    if (!playing) return;
    final expected = generation;
    if (firing) {
      world.setAim(RaidVec.zero, shooting: true);
      accessibleFire?.cancel();
      accessibleFire = Timer(const Duration(milliseconds: 350), () {
        if (current(expected)) world.setAim(RaidVec.zero, shooting: false);
      });
    } else {
      world.setMove(direction);
      accessibleMove?.cancel();
      accessibleMove = Timer(const Duration(milliseconds: 350), () {
        if (current(expected)) world.setMove(RaidVec.zero);
      });
    }
  }

  KeyEventResult keyboard(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      pause();
      return KeyEventResult.handled;
    }
    if (!playing) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      heldKeys.remove(key);
    } else {
      heldKeys.add(key);
    }
    bool pressed(List<LogicalKeyboardKey> keys) => keys.any(heldKeys.contains);
    world.setMove(
      RaidVec(
        (pressed([LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD])
                ? 1.0
                : 0.0) -
            (pressed([LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA])
                    ? 1.0
                    : 0.0)
                .toDouble(),
        (pressed([LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS])
                ? 1.0
                : 0.0) -
            (pressed([LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW])
                    ? 1.0
                    : 0.0)
                .toDouble(),
      ),
    );
    world.setAim(
      RaidVec.zero,
      shooting: heldKeys.contains(LogicalKeyboardKey.space),
    );
    if (event is KeyDownEvent && key == LogicalKeyboardKey.shiftLeft) {
      world.dash();
    }
    if (event is KeyDownEvent && key == LogicalKeyboardKey.keyE) world.shield();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    clearControls();
    loadEpoch++;
    focus.dispose();
    frames.dispose();
    art?.dispose();
    unawaited(sound.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expected = generation;
    final active = permitted;
    return PopScope(
      canPop:
          world.phase == RaidPhase.ready ||
          world.phase == RaidPhase.won ||
          world.phase == RaidPhase.lost,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) pause(exit: true);
      },
      child: Focus(
        focusNode: focus,
        onKeyEvent: keyboard,
        child: ColoredBox(
          color: const Color(0xff081321),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 420;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (art != null)
                    RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('raid-scene'),
                        painter: RayRaidPainter(
                          world: world,
                          art: art!,
                          frames: frames,
                          calmEffects: calmEffects,
                        ),
                      ),
                    ),
                  Positioned(left: 10, right: 10, top: 6, child: hud(expected)),
                  if (art != null &&
                      world.simulating &&
                      active &&
                      !exitQuestion)
                    ...controls(expected, compact),
                  if (art == null ||
                      world.phase != RaidPhase.playing ||
                      world.paused ||
                      !active ||
                      exitQuestion)
                    Positioned.fill(
                      child: BlockSemantics(
                        child: ColoredBox(
                          color: const Color(0xb806101d),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: 430,
                                  maxHeight: constraints.maxHeight - 32,
                                ),
                                child: panel(expected, active),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget hud(int expected) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        decoration: BoxDecoration(
          color: const Color(0xda0b1c2e),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Назад',
                  onPressed: () {
                    if (!current(expected)) return;
                    if (world.phase == RaidPhase.ready ||
                        world.phase == RaidPhase.won ||
                        world.phase == RaidPhase.lost) {
                      exit(expected);
                    } else {
                      pause(exit: true);
                    }
                  },
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: Text(
                    world.mission.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('raid-sound'),
                  tooltip: soundEnabled ? 'Выключить звук' : 'Включить звук',
                  onPressed: () {
                    if (!current(expected)) return;
                    setState(() => soundEnabled = !soundEnabled);
                    if (!soundEnabled) sound.silence();
                  },
                  icon: Icon(
                    soundEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    color: const Color(0xff8fe9f1),
                  ),
                ),
                IconButton(
                  key: const ValueKey('raid-pause'),
                  tooltip: 'Пауза',
                  onPressed: () {
                    if (current(expected)) pause();
                  },
                  icon: const Icon(Icons.pause_rounded, color: Colors.white),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label:
                          'Прочность ${world.health.ceil()} из ${world.maxHealth.ceil()}',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xffff8d92),
                            size: 18,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '${world.health.ceil()}/${world.maxHealth.ceil()}',
                              key: const ValueKey('raid-health'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (world.escorting) ...[
                    const Icon(
                      Icons.local_shipping_outlined,
                      color: Color(0xff9bf1d0),
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Semantics(
                      label:
                          'Грузовик: прочность ${world.convoy.health.ceil()} из 8',
                      child: Text(
                        '${world.convoy.health.ceil()}/8',
                        key: const ValueKey('raid-convoy-health'),
                        style: const TextStyle(
                          color: Color(0xff9bf1d0),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (world.mission == RaidMission.rescue) ...[
                    const Icon(
                      Icons.smart_toy_outlined,
                      color: Color(0xff9bf1d0),
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Semantics(
                      label:
                          'Спасено роботов: ${world.rescuedBots.length} из 3',
                      child: Text(
                        '${world.rescuedBots.length}/3',
                        key: const ValueKey('raid-rescued'),
                        style: const TextStyle(
                          color: Color(0xff9bf1d0),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  const Icon(
                    Icons.battery_charging_full_rounded,
                    color: Color(0xff6cefff),
                    size: 21,
                  ),
                  Text(
                    '${world.coreCount}/3',
                    key: const ValueKey('raid-cores'),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(width: 18),
                  const Icon(
                    Icons.build_circle_outlined,
                    color: Color(0xffffbd64),
                    size: 19,
                  ),
                  Text(
                    ' ${world.moduleCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 7),
      Container(
        constraints: const BoxConstraints(maxWidth: 235),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xc70b1c2e),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          world.objective,
          key: const ValueKey('raid-objective'),
          style: const TextStyle(
            color: Color(0xffffcd82),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  List<Widget> controls(int expected, bool compact) {
    final size = compact ? 100.0 : 126.0;
    return [
      Positioned(
        left: 15,
        bottom: 14,
        child: RaidStick(
          key: ValueKey('raid-move-$expected'),
          label: 'Движение',
          size: size,
          onInput: (v, pressed) {
            if (current(expected) && playing) {
              world.setMove(pressed ? v : RaidVec.zero);
            }
          },
          onAccessibleMove: (v) {
            if (current(expected)) semanticInput(v, false);
          },
        ),
      ),
      Positioned(
        right: 15,
        bottom: 14,
        child: RaidStick(
          key: ValueKey('raid-aim-$expected'),
          label: 'Огонь',
          firing: true,
          size: size,
          onInput: (v, pressed) {
            if (current(expected) && playing) {
              world.setAim(v, shooting: pressed);
            }
          },
          onAccessibleMove: (v) {
            if (current(expected)) semanticInput(v, true);
          },
        ),
      ),
      Positioned(
        right: compact ? 130 : 14,
        bottom: compact ? 20 : 153,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RaidAbilityButton(
              key: const ValueKey('raid-dash'),
              label: 'Рывок',
              icon: Icons.bolt_rounded,
              color: const Color(0xffffbd64),
              remaining: world.dashCooldown,
              recharge: world.dashRecharge,
              onPressed: () {
                if (current(expected) && playing) {
                  world.dash();
                  setState(() {});
                }
              },
            ),
            const SizedBox(width: 12),
            RaidAbilityButton(
              key: const ValueKey('raid-shield'),
              label: 'Щит',
              icon: Icons.shield_outlined,
              color: const Color(0xff6cefff),
              remaining: world.shieldCooldown,
              recharge: world.shieldRecharge,
              onPressed: () {
                if (current(expected) && playing) {
                  world.shield();
                  setState(() {});
                }
              },
            ),
          ],
        ),
      ),
    ];
  }

  Widget action(String text, VoidCallback onPressed, {String? key}) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: FilledButton(
      key: key == null ? null : ValueKey(key),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xffffba5c),
        foregroundColor: const Color(0xff112039),
        minimumSize: const Size(double.infinity, 54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
    ),
  );
  Widget line(String text) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xffd9e8f2),
        fontSize: 16,
        height: 1.35,
      ),
    ),
  );

  Widget panel(int expected, bool active) {
    final children = <Widget>[];
    final readyToStart =
        active &&
        art != null &&
        loadFailure == null &&
        world.phase == RaidPhase.ready &&
        !world.paused &&
        !exitQuestion;
    String title;
    if (!active) {
      title = 'Вылазка приостановлена';
      children.add(line('Вернись в приложение, затем продолжи игру.'));
    } else if (loadFailure != null) {
      title = 'Не удалось открыть уровень';
      children.addAll([
        line('Рисунки не загрузились. Можно попробовать ещё раз.'),
        action('Повторить загрузку', () {
          if (current(expected)) {
            setState(() => loadFailure = null);
            unawaited(load());
          }
        }, key: 'raid-reload'),
        action('Вернуться', () => exit(expected)),
      ]);
    } else if (art == null) {
      title = 'Готовим вылазку';
      children.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: CircularProgressIndicator(color: Color(0xff70edff)),
          ),
        ),
      );
    } else if (exitQuestion || world.paused) {
      title = exitQuestion ? 'Вернуться на корабль?' : 'Пауза';
      children.addAll([
        line(
          exitQuestion
              ? 'Текущую вылазку можно будет начать заново.'
              : 'Лучик подождёт. Продолжай, когда захочешь.',
        ),
        action('Продолжить', () => resume(expected), key: 'raid-resume'),
        action('Выйти на карту', () => exit(expected), key: 'raid-exit'),
      ]);
    } else if (world.phase == RaidPhase.ready) {
      title = world.mission.title.toUpperCase();
      children.addAll([
        SizedBox(height: 72, child: CustomPaint(painter: _RaidPortrait(art!))),
        line('Выбери миссию — все девять доступны сразу.'),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final mission in RaidMission.values)
              ChoiceChip(
                key: ValueKey('raid-mission-${mission.name}'),
                label: Text('${mission.index + 1}. ${mission.title}'),
                selected: world.mission == mission,
                onSelected: (_) => selectMission(expected, mission),
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ],
        ),
        line(world.mission.briefing),
        if (world.mission == RaidMission.magnet)
          line(
            'Щитоносец с оранжевым кругом открыт для атаки. Голубой круг — защита включена.',
          ),
        if (world.mission == RaidMission.foundry ||
            world.mission == RaidMission.dock)
          line(
            'Оранжевый перехватчик сначала прицеливается, потом летит прямо. Зелёный ремонтник чинит соседей — отключай его первым.',
          ),
        if (world.mission == RaidMission.convoy ||
            world.mission == RaidMission.storm)
          line(
            'Лучевой дрон сначала показывает прицел. Метка на полу — место будущего разряда: успей выйти из круга.',
          ),
        if (world.mission == RaidMission.rescue ||
            world.mission == RaidMission.meteor)
          line(
            'Прыгун показывает розовый круг перед прыжком. Кольцевая волна проходит над ящиками — отойди или включи щит.',
          ),
        line('Слева — движение. Справа — огонь: удерживай или веди прицел.'),
        line(
          'Рывок — уклониться. Щит — защититься. Энергоблок — починиться и стать сильнее.',
        ),
        TextButton(
          onPressed: () => exit(expected),
          child: const Text(
            'Вернуться',
            style: TextStyle(color: Color(0xffb5e5ec)),
          ),
        ),
      ]);
    } else if (world.phase == RaidPhase.upgrade) {
      title = 'ЭНЕРГОБЛОК НАЙДЕН';
      children.add(
        line('Выбери модуль. Улучшение действует до конца этой вылазки.'),
      );
      for (final u in RaidUpgrade.values) {
        if (world.upgrades[u]! >= 2) continue;
        final level = world.upgrades[u]!;
        final (name, description, icon) = switch (u) {
          RaidUpgrade.pulse => (
            'Двойной импульс',
            level == 0 ? 'Два заряда вместо одного' : 'Более быстрый огонь',
            Icons.auto_awesome_rounded,
          ),
          RaidUpgrade.dash => (
            'Искровой двигатель',
            level == 0
                ? 'Рывок перезаряжается быстрее'
                : 'Дальше рывок, короче ожидание',
            Icons.bolt_rounded,
          ),
          RaidUpgrade.shield => (
            'Защитный купол',
            level == 0
                ? 'Прочнее щит и больше здоровья'
                : 'Ещё больше защиты и прочности',
            Icons.shield_outlined,
          ),
          RaidUpgrade.companion => (
            'Дрон-напарник',
            level == 0
                ? 'Летает рядом и помогает стрелять'
                : 'Напарник стреляет быстрее',
            Icons.smart_toy_outlined,
          ),
          RaidUpgrade.pierce => (
            'Сквозной импульс',
            level == 0
                ? 'Заряд проходит сквозь одного дрона'
                : 'Заряд проходит сквозь двух дронов',
            Icons.double_arrow_rounded,
          ),
          RaidUpgrade.frost => (
            'Ледяной щит',
            level == 0
                ? 'Включённый щит замедляет рядом дронов и заряды'
                : 'Больше круг замедления и сильнее эффект',
            Icons.ac_unit_rounded,
          ),
          RaidUpgrade.chain => (
            'Цепной импульс',
            level == 0
                ? 'Цепь по соседям, усиленный удар по одиночному'
                : 'Две связи и сильнее одиночный удар',
            Icons.hub_outlined,
          ),
          RaidUpgrade.reflect => (
            'Зеркальный щит',
            level == 0
                ? 'Включённый щит возвращает заряды дронам'
                : 'Отражённый заряд сильнее и пробивает дрона',
            Icons.undo_rounded,
          ),
          RaidUpgrade.shock => (
            'Ударный рывок',
            level == 0
                ? 'В начале рывка волна отталкивает дронов рядом'
                : 'Шире волна и сильнее удар',
            Icons.waves_rounded,
          ),
          RaidUpgrade.ricochet => (
            'Рикошетный импульс',
            level == 0
                ? 'Твои заряды один раз отскакивают от ящиков и стен'
                : 'Два отскока вместо одного',
            Icons.turn_slight_right_rounded,
          ),
          RaidUpgrade.orbit => (
            'Орбитальный страж',
            level == 0
                ? 'Маленький защитник перехватывает заряд рядом раз в 3 секунды'
                : 'Перехватывает заряды чаще и дальше от Лучика',
            Icons.satellite_alt_rounded,
          ),
        };
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              key: ValueKey('raid-upgrade-${u.name}'),
              onPressed: () => choose(expected, u),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xff4d7789)),
                padding: const EdgeInsets.all(16),
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xff1a3b50),
              ),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xffffc16a), size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$name${level == 1 ? ' II' : ''}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xffb9d5e2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      children.add(
        TextButton(
          onPressed: () {
            if (current(expected)) pause(exit: true);
          },
          child: const Text(
            'Пауза / выйти',
            style: TextStyle(color: Color(0xffb5e5ec)),
          ),
        ),
      );
    } else {
      final won = world.phase == RaidPhase.won;
      title = won
          ? world.mission.victory
          : world.escorting && world.convoy.health == 0
          ? 'КОНВОЮ НУЖЕН РЕМОНТ'
          : 'ПЕРЕЗАГРУЗКА';
      children.addAll([
        Icon(
          won ? Icons.auto_awesome_rounded : Icons.restart_alt_rounded,
          color: const Color(0xff7aeeff),
          size: 58,
        ),
        line(
          won
              ? '${world.mission.ending} Вылазка завершена!'
              : world.mission == RaidMission.meteor ||
                    world.mission == RaidMission.rescue
              ? 'Лучику нужна перезагрузка. Следи за кругами на полу и кольцевыми волнами. Рывок и щит помогут уклониться. Можно попробовать снова.'
              : 'Лучику нужна перезагрузка. Попробуй укрытия, рывок и щит — и выбирай другой маршрут.',
        ),
        line(
          'Энергоблоки: ${world.coreCount}/3   ·   Модули: ${world.moduleCount}\nДроны отключены: ${world.disabledDrones}',
        ),
        if (world.relaysDisabled > 0)
          line('Генераторы отключены: ${world.relaysDisabled}'),
        if (world.escorting)
          line('Прочность грузовика: ${world.convoy.health.ceil()}/8'),
        if (world.mission == RaidMission.rescue)
          line('Друзья на площадках: ${world.rescuedBots.length}/3'),
        if (won && world.mission.index < RaidMission.values.length - 1)
          action(
            'Следующая миссия',
            () => selectMission(
              expected,
              RaidMission.values[world.mission.index + 1],
            ),
            key: 'raid-next-mission',
          ),
        action(
          'Ещё вылазка',
          () => begin(expected, replay: true),
          key: 'raid-replay',
        ),
        action(
          'Выбрать миссию',
          () => selectMission(expected, world.mission),
          key: 'raid-missions',
        ),
        action('На карту', () => exit(expected), key: 'raid-exit'),
      ]);
    }
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: title,
      child: Material(
        color: const Color(0xff10283d),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xff3c6178)),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  key: ValueKey(
                    'raid-panel-${world.phase.name}-${world.mission.name}',
                  ),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        key: const ValueKey('raid-panel-title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...children,
                    ],
                  ),
                ),
              ),
              if (readyToStart)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                  child: action(
                    'Начать вылазку',
                    () => begin(expected),
                    key: 'raid-start',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RaidPortrait extends CustomPainter {
  final RayRaidArt art;
  _RaidPortrait(this.art);
  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide.clamp(0.0, 110.0).toDouble();
    canvas.drawImageRect(
      art.sprites,
      const Rect.fromLTWH(0, 0, 512, 512),
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: side,
        height: side,
      ),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant _RaidPortrait old) => !identical(art, old.art);
}
