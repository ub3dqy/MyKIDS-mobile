import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/ray_raid_audio.dart';
import 'package:mykids_family/engagement/ray_raid_controls.dart';
import 'package:mykids_family/engagement/ray_raid_game.dart';
import 'package:mykids_family/engagement/ray_raid_model.dart';
import 'package:mykids_family/engagement/ray_raid_painter.dart';
import 'package:mykids_family/visuals.dart';

class QuietRaidSound implements RaidSound {
  final events = <RaidEffectKind>[];
  int stops = 0;
  bool disposed = false;
  @override
  void play(RaidEffectKind kind) {
    if (!disposed) events.add(kind);
  }

  @override
  void silence() {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  final oldDesign = gameDesign.value;
  final surface = GlobalKey();
  late RayRaidWorld world;
  late QuietRaidSound sound;
  var allowed = true, exits = 0;
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    world = RayRaidWorld();
    sound = QuietRaidSound();
    allowed = true;
    exits = 0;
    gameDesign.value = GameDesign.byId('squad');
  });
  tearDown(() => gameDesign.value = oldDesign);

  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    if (tester.view.physicalSize / tester.view.devicePixelRatio ==
        const Size(800, 600)) {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final art = await tester.runAsync(RayRaidArt.load);
    expect(art, isNotNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: familyTheme(true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: surface,
            child: RayRaidGame(
              canPlay: () => allowed,
              onExit: () => exits++,
              initialWorld: world,
              sound: sound,
              loadArt: () async => art!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 16));
  }

  Future<void> frames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Finder stick(String label) =>
      find.byWidgetPredicate((w) => w is RaidStick && w.label == label);
  Future<void> capture(WidgetTester tester, String name) async {
    const path = String.fromEnvironment('RAID_CAPTURE_DIR');
    if (path.isEmpty) return;
    final root = Directory(path).absolute;
    expect(
      root.path.replaceAll('\\', '/'),
      contains('/docs/ray-campaign-114-2026-10-27/'),
    );
    root.createSync(recursive: true);
    final boundary =
        surface.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${root.path}/$name.png');
      expect(file.existsSync(), false);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('intro is a real loaded arena and exit/start are usable', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('raid-scene')), findsOneWidget);
    expect(find.text('ЛУННЫЙ МАЯК'), findsOneWidget);
    await capture(tester, 'intro');
    await tap(tester, 'raid-start');
    expect(world.phase, RaidPhase.playing);
    expect(stick('Движение'), findsOneWidget);
    expect(stick('Огонь'), findsOneWidget);
    expect(exits, 0);
  });
  testWidgets(
    'two independent thumbs move and fire simultaneously; release clears input',
    (tester) async {
      await mount(tester);
      await tap(tester, 'raid-start');
      final move = await tester.startGesture(
        tester.getCenter(stick('Движение')),
        pointer: 10,
      );
      await move.moveBy(const Offset(-32, -28));
      final aim = await tester.startGesture(
        tester.getCenter(stick('Огонь')),
        pointer: 11,
      );
      await frames(tester, 35);
      expect(world.player.distance(raidStart), greaterThan(30));
      expect(world.effects.any((e) => e.kind == RaidEffectKind.shot), true);
      await capture(tester, 'arena');
      await move.up();
      await aim.up();
      await tester.pump();
      expect(world.movement.length, 0);
      expect(world.firing, false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dash and shield activate with visible cooldown and cannot be spammed',
    (tester) async {
      await mount(tester);
      await tap(tester, 'raid-start');
      await tap(tester, 'raid-dash');
      await tap(tester, 'raid-shield');
      expect(world.dashUses, 1);
      expect(world.shieldUses, 1);
      await tap(tester, 'raid-dash');
      await tap(tester, 'raid-shield');
      expect(world.dashUses, 1);
      expect(world.shieldUses, 1);
      await frames(tester, 10);
      expect(world.shieldTime, greaterThan(0));
    },
  );
  testWidgets(
    'pause stops physics and sound; old touch callbacks cannot affect resumed play',
    (tester) async {
      await mount(tester);
      await tap(tester, 'raid-start');
      final old = tester.widget<RaidStick>(stick('Движение')).onInput;
      final oldAbility = tester
          .widget<RaidAbilityButton>(find.byKey(const ValueKey('raid-dash')))
          .onPressed;
      final drag = await tester.startGesture(
        tester.getCenter(stick('Движение')),
        pointer: 12,
      );
      await drag.moveBy(const Offset(24, 0));
      await frames(tester, 8);
      await tap(tester, 'raid-pause');
      final position = world.player, time = world.elapsed;
      await tester.pump(const Duration(seconds: 5));
      expect(world.player.distance(position), 0);
      expect(world.elapsed, time);
      expect(sound.stops, greaterThan(0));
      final resume = tester
          .widget<FilledButton>(find.byKey(const ValueKey('raid-resume')))
          .onPressed!;
      await tap(tester, 'raid-resume');
      old(const RaidVec(1, 0), true);
      oldAbility();
      resume();
      await drag.up();
      await frames(tester, 10);
      expect(world.player.distance(position), 0);
      expect(world.dashUses, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'backgrounding and route permission changes pause immediately and require resume',
    (tester) async {
      await mount(tester);
      await tap(tester, 'raid-start');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final time = world.elapsed;
      await tester.pump(const Duration(seconds: 10));
      expect(world.elapsed, time);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(world.paused, true);
      await tap(tester, 'raid-resume');
      await frames(tester, 3);
      allowed = false;
      await frames(tester, 3);
      final stopped = world.elapsed;
      await frames(tester, 6);
      expect(world.elapsed, stopped);
      expect(world.paused, true);
      allowed = true;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(sound.disposed, true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('keyboard supports movement, fire and both abilities', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'raid-start');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
    await frames(tester, 8);
    expect(world.player.x, lessThan(raidStart.x));
    expect(world.dashUses, 1);
    expect(world.shieldUses, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
    expect(world.firing, false);
  });
  testWidgets(
    'upgrade choice changes mechanics and old choices cannot add another module',
    (tester) async {
      world.start();
      world.coreUnlocked = true;
      world.player = raidCores[0];
      world.advance(.02);
      await mount(tester);
      final old = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('raid-upgrade-pulse')),
          )
          .onPressed!;
      await capture(tester, 'upgrade');
      await tap(tester, 'raid-upgrade-pulse');
      old();
      await frames(tester, 3);
      expect(world.moduleCount, 1);
      expect(world.upgrades[RaidUpgrade.pulse], 1);
      expect(world.phase, RaidPhase.playing);
    },
  );
  testWidgets('replay resets local run and rejects stale result callbacks', (
    tester,
  ) async {
    world.phase = RaidPhase.won;
    world.collected.addAll([0, 1, 2]);
    world.upgrades[RaidUpgrade.dash] = 2;
    await mount(tester);
    final old = tester
        .widget<FilledButton>(find.byKey(const ValueKey('raid-replay')))
        .onPressed!;
    await capture(tester, 'won');
    await tap(tester, 'raid-replay');
    old();
    await frames(tester, 3);
    final fresh =
        (tester.state(find.byType(RayRaidGame)) as dynamic).world
            as RayRaidWorld;
    expect(fresh.phase, RaidPhase.playing);
    expect(fresh.coreCount, 0);
    expect(fresh.moduleCount, 0);
    expect(fresh.health, 6);
  });
  testWidgets(
    'late asset completion and pointer callbacks are harmless after disposal',
    (tester) async {
      final ready = Completer<RayRaidArt>();
      final art = await tester.runAsync(RayRaidArt.load);
      await tester.pumpWidget(
        MaterialApp(
          home: RayRaidGame(
            canPlay: () => true,
            onExit: () {},
            sound: sound,
            loadArt: () => ready.future,
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      ready.complete(art!);
      await tester.pump();
      expect(sound.disposed, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: RaidStick(
            label: 'Тест',
            onInput: (_, _) {},
            onAccessibleMove: (_) {},
          ),
        ),
      );
      final listener = tester.widget<Listener>(find.byType(Listener).last);
      await tester.pumpWidget(const SizedBox.shrink());
      listener.onPointerDown?.call(const PointerDownEvent(pointer: 42));
      listener.onPointerMove?.call(const PointerMoveEvent(pointer: 42));
      listener.onPointerUp?.call(const PointerUpEvent(pointer: 42));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('audio toggle silences effects and remains safe on pause', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'raid-start');
    await tap(tester, 'raid-sound');
    final count = sound.events.length;
    final fire = await tester.startGesture(
      tester.getCenter(stick('Огонь')),
      pointer: 18,
    );
    await frames(tester, 20);
    await fire.up();
    expect(sound.events.length, count);
    expect(sound.stops, greaterThan(0));
  });
  testWidgets(
    'missions are free to select and stale selection cannot replace a started run',
    (tester) async {
      await mount(tester);
      final old = tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('raid-mission-dock')))
          .onSelected!;
      await tap(tester, 'raid-mission-foundry');
      await tap(tester, 'raid-start');
      old(true);
      final active =
          (tester.state(find.byType(RayRaidGame)) as dynamic).world
              as RayRaidWorld;
      expect(active.mission, RaidMission.foundry);
      expect(active.phase, RaidPhase.playing);
      expect(active.hazards, hasLength(3));
      await frames(tester, 3);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'next mission requires a separate start and replay keeps the selected mission',
    (tester) async {
      world = RayRaidWorld(mission: RaidMission.foundry)..phase = RaidPhase.won;
      await mount(tester);
      await tap(tester, 'raid-next-mission');
      RayRaidWorld active() =>
          (tester.state(find.byType(RayRaidGame)) as dynamic).world
              as RayRaidWorld;
      expect(active().mission, RaidMission.dock);
      expect(active().phase, RaidPhase.ready);
      expect(active().elapsed, 0);
      expect(active().moduleCount, 0);
      await tap(tester, 'raid-start');
      expect(active().mission, RaidMission.dock);
      expect(active().relayAlive, true);
      await tester.pumpWidget(const SizedBox.shrink());
      world = RayRaidWorld(mission: RaidMission.dock)..phase = RaidPhase.lost;
      sound = QuietRaidSound();
      await mount(tester);
      await tap(tester, 'raid-replay');
      expect(active().mission, RaidMission.dock);
      expect(active().phase, RaidPhase.playing);
    },
  );
  testWidgets('revoked access rejects captured mission and module callbacks', (
    tester,
  ) async {
    await mount(tester);
    final choose = tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('raid-mission-dock')))
        .onSelected!;
    allowed = false;
    choose(true);
    expect(
      (tester.state(find.byType(RayRaidGame)) as dynamic).world,
      same(world),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    world = RayRaidWorld(mission: RaidMission.dock)..phase = RaidPhase.upgrade;
    allowed = true;
    sound = QuietRaidSound();
    await mount(tester);
    final upgrade = tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('raid-upgrade-companion')),
        )
        .onPressed!;
    allowed = false;
    upgrade();
    expect(world.moduleCount, 0);
  });
  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'intro, active controls and upgrades fit$size at text$scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await mount(tester, scale: scale);
          for (final mission in RaidMission.values) {
            await tap(tester, 'raid-mission-${mission.name}');
            expect(
              find.byKey(const ValueKey('raid-start')).hitTestable(),
              findsOneWidget,
            );
            expect(
              tester.getRect(find.byKey(const ValueKey('raid-start'))).bottom,
              lessThanOrEqualTo(size.height),
            );
          }
          await tap(tester, 'raid-mission-convoy');
          await tap(tester, 'raid-start');
          expect(
            tester.getSize(stick('Движение')).width,
            greaterThanOrEqualTo(100),
          );
          expect(
            tester.getSize(find.byKey(const ValueKey('raid-shield'))).width,
            greaterThanOrEqualTo(48),
          );
          await tap(tester, 'raid-pause');
          await tap(tester, 'raid-resume');
          await frames(tester, 4);
          expect(tester.takeException(), isNull);
          for (final module in [
            RaidUpgrade.frost,
            RaidUpgrade.reflect,
            RaidUpgrade.shock,
            RaidUpgrade.ricochet,
            RaidUpgrade.orbit,
          ]) {
            await tester.pumpWidget(const SizedBox.shrink());
            world = RayRaidWorld()..start();
            world.coreUnlocked = true;
            world.player = raidCores[0];
            world.advance(.02);
            sound = QuietRaidSound();
            await mount(tester, scale: scale);
            await tap(tester, 'raid-upgrade-${module.name}');
            await frames(tester, 3);
            expect(world.moduleCount, 1);
            expect(world.upgrades[module], 1);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
