import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/discovery_catalog.dart';
import 'package:mykids_family/engagement/discovery_page.dart';
import 'package:mykids_family/engagement/robot_route_game.dart';
import 'package:mykids_family/engagement/space_memory_game.dart';
import 'package:mykids_family/engagement/robot_workshop_game.dart';
import 'package:mykids_family/engagement/ray_raid_game.dart';
import 'package:mykids_family/engagement/ray_raid_controls.dart';
import 'package:mykids_family/engagement/ray_raid_model.dart';
import 'package:mykids_family/engagement/engagement_entries.dart';
import 'package:mykids_family/engagement/engagement_scope.dart';
import 'package:mykids_family/engagement/preview_controller.dart';
import 'package:mykids_family/engagement/production_controller.dart';
import 'package:mykids_family/visuals.dart';

import 'support/engagement_fixture.dart';

const captureRoot = String.fromEnvironment('DISCOVERY_CAPTURE_DIR');
final captureSurface = GlobalKey();

class DiscoveryRepository extends ProductionFixtureRepository {
  final writes = <String>[];
  DiscoveryRepository(super.preview) {
    play['confirmed_total'] = 0;
    publish();
  }
  @override
  Future<List<Map<String, dynamic>>> pending() async => [];
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    writes.add(path);
    return {};
  }
}

void main() {
  late PreviewEngagementController preview;
  late DiscoveryRepository repo;
  late ProductionEngagementController controller;
  final oldDesign = gameDesign.value;

  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    if (captureRoot.isEmpty) return;
    await tester.pumpAndSettle();
    final folder = Directory(captureRoot).absolute;
    expect(
      folder.path.replaceAll('\\', '/'),
      contains('/docs/ray-campaign-114-2026-10-27/'),
    );
    folder.createSync(recursive: true);
    final file = File('${folder.path}/$name.png');
    expect(file.existsSync(), false);
    final boundary =
        captureSurface.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  setUp(() {
    gameDesign.value = GameDesign.byId('squad');
    preview = PreviewEngagementController(
      EngagementReviewRepository(),
      save: (_) async {},
    );
    repo = DiscoveryRepository(preview);
    controller = ProductionEngagementController(repo);
  });
  tearDown(() {
    controller.dispose();
    repo.client.close();
    repo.dispose();
    preview.dispose();
    gameDesign.value = oldDesign;
  });

  Future<void> mount(
    WidgetTester tester, {
    double scale = 1,
    VoidCallback? tasks,
  }) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      EngagementScope(
        controller: controller,
        child: MaterialApp(
          theme: familyTheme(true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: captureSurface, child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/play/discoveries'),
                    builder: (_) => DiscoveryPage(onTasks: tasks),
                  ),
                ),
                child: const Text('Открыть космос'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть космос'));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      220,
      maxScrolls: 80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> stop(WidgetTester tester, String id) async {
    final world = spaceDiscoveries.firstWhere((s) => s.id == id).world;
    final header = find.byKey(ValueKey('discovery-world-$world'));
    await reveal(tester, header);
    final tile = find.byKey(ValueKey('discovery-$id'));
    if (tile.evaluate().isEmpty) {
      await tester.tap(header);
      await tester.pumpAndSettle();
    }
    await reveal(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  test('catalogue boundaries open exactly once from confirmed totals', () {
    expect(spaceDiscoveries, hasLength(30));
    expect(spaceWorlds, hasLength(10));
    expect(spaceDiscoveries.map((s) => s.id).toSet(), hasLength(30));
    for (var i = 0; i < spaceDiscoveries.length; i++) {
      final s = spaceDiscoveries[i];
      expect(s.world, i ~/ 3);
      expect(s.answer, inInclusiveRange(0, s.choices.length - 1));
      expect(s.choices.toSet(), hasLength(3));
      expect(discoveriesOpen(s.tasks), i + 1);
      if (i > 0) expect(discoveriesOpen(s.tasks - 1), i);
      expect(
        s.story.isNotEmpty && s.hint.isNotEmpty && s.ending.isNotEmpty,
        true,
      );
    }
    expect(nextDiscovery(160), isNull);
    expect(discoveriesOpen(1000000000), 30);
  });

  test('remaining work uses natural Russian counts', () {
    expect([0, 1, 2, 5, 11, 14, 21, 24, 45].map(discoveryTaskCount), [
      '0 дел',
      '1 дело',
      '2 дела',
      '5 дел',
      '11 дел',
      '14 дел',
      '21 дело',
      '24 дела',
      '45 дел',
    ]);
  });

  testWidgets('first story is free and choices cannot earn tasks or money', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = repo.snapshot!['balance'].toString();
    await mount(tester);
    expect(find.text('Открыто находок: 1 из 30'), findsOneWidget);
    await capture(tester, 'map-first');
    await stop(tester, 'launch');
    await capture(tester, 'riddle-first');
    await reveal(tester, find.byKey(const ValueKey('discovery-answer-1')));
    await tester.tap(find.byKey(const ValueKey('discovery-answer-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Подсказка:'), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('discovery-feedback')));
    await capture(tester, 'riddle-hint');
    await reveal(tester, find.byKey(const ValueKey('discovery-answer-0')));
    await tester.tap(find.byKey(const ValueKey('discovery-answer-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Верно!'), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('discovery-feedback')));
    await capture(tester, 'riddle-solved');
    expect(repo.writes, isEmpty);
    expect(controller.completedCount, 0);
    expect(repo.snapshot!['balance'].toString(), before);
    await reveal(tester, find.text('Назад к карте'));
    await tester.tap(find.text('Назад к карте'));
    await tester.pumpAndSettle();
    expect(find.text('Открыто находок: 1 из 30'), findsOneWidget);
  });

  testWidgets(
    'cached server count persists and pending or forged local tasks do not unlock finds',
    (tester) async {
      await mount(tester);
      controller.state.confirmedTasks.addAll(['local-a', 'local-b', 'local-c']);
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Открыто находок: 1 из 30'), findsOneWidget);
      repo.online = false;
      repo.play['confirmed_total'] = 2;
      repo.publish();
      await tester.pumpAndSettle();
      expect(find.text('Открыто находок: 3 из 30'), findsOneWidget);
      await stop(tester, 'luggage');
      expect(
        find.textContaining('Твоя находка: Рюкзак Лучика'),
        findsOneWidget,
      );
      expect(repo.writes, isEmpty);
    },
  );

  testWidgets('locked stop hides riddle and safely returns to actual tasks', (
    tester,
  ) async {
    var openedTasks = 0;
    await mount(tester, tasks: () => openedTasks++);
    await stop(tester, 'beacon');
    expect(find.text('Сигнал для корабля'), findsOneWidget);
    expect(find.text('Загадка Лучика'), findsNothing);
    expect(find.byKey(const ValueKey('discovery-answer-0')), findsNothing);
    await reveal(tester, find.text('Выбрать дело'));
    final old = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Выбрать дело'))
        .onPressed!;
    old();
    old();
    await tester.pumpAndSettle();
    expect(openedTasks, 1);
    expect(find.text('Открыть космос'), findsOneWidget);
    expect(repo.writes, isEmpty);
  });

  for (final revocation in ['session', 'role', 'feature']) {
    testWidgets(
      'open story permanently masks after $revocation revocation and restoration',
      (tester) async {
        await mount(tester);
        await stop(tester, 'launch');
        await reveal(tester, find.byKey(const ValueKey('discovery-answer-0')));
        final old = tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('discovery-answer-0')),
            )
            .onPressed!;
        if (revocation == 'session') {
          repo.generation++;
          repo.notifyListeners();
        } else if (revocation == 'role') {
          repo.snapshot!['user']['role'] = 'relative';
          repo.publish();
          repo.snapshot!['user']['role'] = 'child';
          repo.publish();
        } else {
          repo.play['state']['enabled']['adventure'] = false;
          repo.publish();
          repo.play['state']['enabled']['adventure'] = true;
          repo.publish();
        }
        old();
        await tester.pumpAndSettle();
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        expect(find.text('Загадка Лучика'), findsNothing);
        expect(find.textContaining('Верно!'), findsNothing);
        expect(repo.writes, isEmpty);
      },
    );
  }

  testWidgets(
    'covered answer and captured back button cannot change the important route',
    (tester) async {
      await mount(tester);
      await stop(tester, 'launch');
      await reveal(tester, find.byKey(const ValueKey('discovery-answer-0')));
      final answer = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('discovery-answer-0')),
          )
          .onPressed!;
      final back = tester
          .widget<BackButton>(find.byType(BackButton).last)
          .onPressed!;
      final nav = Navigator.of(tester.element(find.byType(DiscoveryStopPage)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Важный экран')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      answer();
      back();
      await tester.pumpAndSettle();
      expect(find.text('Важный экран'), findsOneWidget);
      expect(find.textContaining('Верно!', skipOffstage: false), findsNothing);
      expect(repo.writes, isEmpty);
    },
  );

  testWidgets(
    'removing the app scope during logout hides an already open story',
    (tester) async {
      final attached = ValueNotifier(true);
      final navigation = GlobalKey<NavigatorState>();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        attached.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigation,
          theme: familyTheme(true),
          builder: (_, child) => ValueListenableBuilder<bool>(
            valueListenable: attached,
            builder: (_, enabled, _) => enabled
                ? EngagementScope(controller: controller, child: child!)
                : child!,
          ),
          home: const Scaffold(body: Text('Главная')),
        ),
      );
      unawaited(
        navigation.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => DiscoveryStopPage(stop: spaceDiscoveries.first),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Загадка Лучика'), findsOneWidget);
      attached.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryStopPage), findsOneWidget);
      expect(find.textContaining('Доступ изменился.'), findsOneWidget);
      expect(find.text('Загадка Лучика'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new quick entry follows parent control even with hero and missions off',
    (tester) async {
      repo.play['state']['enabled']['hero'] = false;
      repo.play['state']['enabled']['family'] = false;
      repo.publish();
      await tester.pumpWidget(
        EngagementScope(
          controller: controller,
          child: MaterialApp(
            theme: familyTheme(true),
            home: const Scaffold(body: HeroHomeActions()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Космос'), findsOneWidget);
      final old = tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Космос'))
          .onPressed!;
      repo.generation++;
      repo.notifyListeners();
      old();
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryPage), findsNothing);
      repo.play['state']['enabled']['adventure'] = false;
      repo.publish();
      await tester.pumpAndSettle();
      expect(find.text('Космос'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> training(WidgetTester tester) async {
    final entry = find.byKey(const ValueKey('robot-training-entry'));
    await reveal(tester, entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(RobotTrainingPage), findsOneWidget);
  }

  testWidgets(
    'continue opens the latest confirmed find without expanding worlds',
    (tester) async {
      repo.play['confirmed_total'] = 72;
      repo.publish();
      await mount(tester);
      await reveal(tester, find.byKey(const ValueKey('discovery-continue')));
      await tester.tap(find.byKey(const ValueKey('discovery-continue')));
      await tester.pumpAndSettle();
      expect(
        find.text('Твоя находка: Пульт маленького курьера'),
        findsOneWidget,
      );
      expect(repo.writes, isEmpty);
    },
  );

  testWidgets(
    'collapsed new worlds reveal locked finds without unlocking their stories',
    (tester) async {
      await mount(tester);
      await stop(tester, 'crew-map');
      expect(find.text('Карта космической команды'), findsOneWidget);
      expect(find.text('Загадка Лучика'), findsNothing);
      expect(find.textContaining('ещё 100 дел'), findsOneWidget);
      expect(controller.completedCount, 0);
      expect(repo.writes, isEmpty);
    },
  );

  for (final revocation in ['session', 'role', 'feature']) {
    testWidgets('robot training masks permanently after $revocation changes', (
      tester,
    ) async {
      await mount(tester);
      await training(tester);
      await reveal(tester, find.byKey(const ValueKey('robot-challenge-1')));
      final change = tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('robot-challenge-1')))
          .onSelected!;
      await reveal(tester, find.byKey(const ValueKey('robot-up')));
      final move = tester
          .widget<IconButton>(find.byKey(const ValueKey('robot-up')))
          .onPressed!;
      if (revocation == 'session') {
        repo.generation++;
        repo.notifyListeners();
      } else if (revocation == 'role') {
        repo.snapshot!['user']['role'] = 'parent';
        repo.publish();
        repo.snapshot!['user']['role'] = 'child';
        repo.publish();
      } else {
        repo.play['state']['enabled']['adventure'] = false;
        repo.publish();
        repo.play['state']['enabled']['adventure'] = true;
        repo.publish();
      }
      move();
      change(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('Доступ изменился.'), findsOneWidget);
      expect(find.byType(RobotRouteGame), findsNothing);
      expect(repo.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'covered robot callbacks preserve the covering route and cannot resume old play',
    (tester) async {
      await mount(tester);
      await training(tester);
      await reveal(tester, find.byKey(const ValueKey('robot-up')));
      final move = tester
          .widget<IconButton>(find.byKey(const ValueKey('robot-up')))
          .onPressed!;
      final back = tester
          .widget<BackButton>(find.byType(BackButton).last)
          .onPressed!;
      final nav = Navigator.of(tester.element(find.byType(RobotTrainingPage)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Важный экран')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      move();
      back();
      await tester.pumpAndSettle();
      expect(find.text('Важный экран'), findsOneWidget);
      nav.pop();
      await tester.pumpAndSettle();
      move();
      await tester.pumpAndSettle();
      expect(find.textContaining('Лучик: ряд 4, клетка 1.'), findsOneWidget);
      expect(repo.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> station(WidgetTester tester, {bool workshop = false}) async {
    final entry = find.byKey(const ValueKey('space-station-entry'));
    await reveal(tester, entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(SpaceStationPage), findsOneWidget);
    if (workshop) {
      await tester.tap(find.byKey(const ValueKey('station-game-workshop')));
      await tester.pumpAndSettle();
    }
  }

  for (final workshop in [false, true]) {
    for (final revocation in ['session', 'role', 'feature']) {
      testWidgets(
        'station ${workshop ? 'workshop' : 'pairs'} masks permanently after $revocation',
        (tester) async {
          await mount(tester);
          await station(tester, workshop: workshop);
          final actionKey = workshop ? 'workshop-part-wheels' : 'memory-card-0';
          final action = tester
              .widget<OutlinedButton>(find.byKey(ValueKey(actionKey)))
              .onPressed!;
          final change = tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('station-level-1')))
              .onSelected!;
          if (revocation == 'session') {
            repo.generation++;
            repo.notifyListeners();
          } else if (revocation == 'role') {
            repo.snapshot!['user']['role'] = 'parent';
            repo.publish();
            repo.snapshot!['user']['role'] = 'child';
            repo.publish();
          } else {
            repo.play['state']['enabled']['adventure'] = false;
            repo.publish();
            repo.play['state']['enabled']['adventure'] = true;
            repo.publish();
          }
          action();
          change(true);
          await tester.pumpAndSettle();
          expect(find.textContaining('Доступ изменился.'), findsOneWidget);
          expect(find.byType(SpaceMemoryGame), findsNothing);
          expect(find.byType(RobotWorkshopGame), findsNothing);
          expect(repo.writes, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'station works at zero confirmed tasks; stale mode chips cannot reset new games',
    (tester) async {
      await mount(tester);
      await station(tester);
      final old = tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('station-game-workshop')),
          )
          .onSelected!;
      await tester.tap(find.byKey(const ValueKey('station-game-workshop')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('workshop-part-wheels')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workshop-part-wheels')));
      await tester.pumpAndSettle();
      old(true);
      await tester.pumpAndSettle();
      expect(find.text('Детали робота: 1 из 3'), findsOneWidget);
      expect(controller.completedCount, 0);
      expect(repo.writes, isEmpty);
    },
  );
  testWidgets(
    'covered station callbacks do not close the covering route or change old cards',
    (tester) async {
      await mount(tester);
      await station(tester);
      final flip = tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('memory-card-0')))
          .onPressed!;
      final back = tester
          .widget<BackButton>(find.byType(BackButton).last)
          .onPressed!;
      final nav = Navigator.of(tester.element(find.byType(SpaceStationPage)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Важный экран')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      flip();
      back();
      await tester.pumpAndSettle();
      expect(find.text('Важный экран'), findsOneWidget);
      nav.pop();
      await tester.pumpAndSettle();
      flip();
      await tester.pumpAndSettle();
      expect(find.text('Найдено пар: 0 из 3'), findsOneWidget);
      expect(find.text('Звезда'), findsNothing);
      expect(repo.writes, isEmpty);
    },
  );

  Future<void> raid(WidgetTester tester) async {
    final entry = find.byKey(const ValueKey('ray-raid-entry'));
    await reveal(tester, entry);
    await tester.tap(entry);
    for (
      var i = 0;
      i < 40 && find.byKey(const ValueKey('raid-scene')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('raid-scene')), findsOneWidget);
    await tester.pumpAndSettle();
  }

  for (final revocation in ['session', 'role', 'feature']) {
    testWidgets(
      'raid permanently masks and rejects old controls after $revocation',
      (tester) async {
        await mount(tester);
        await raid(tester);
        final start = tester
            .widget<FilledButton>(find.byKey(const ValueKey('raid-start')))
            .onPressed!;
        if (revocation == 'session') {
          repo.generation++;
          repo.notifyListeners();
        } else if (revocation == 'role') {
          repo.snapshot!['user']['role'] = 'parent';
          repo.publish();
          repo.snapshot!['user']['role'] = 'child';
          repo.publish();
        } else {
          repo.play['state']['enabled']['adventure'] = false;
          repo.publish();
          repo.play['state']['enabled']['adventure'] = true;
          repo.publish();
        }
        start();
        await tester.pumpAndSettle();
        expect(find.byType(RayRaidGame), findsNothing);
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        expect(repo.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'raid pauses beneath another route, rejects stale input and exits through confirmation',
    (tester) async {
      await mount(tester);
      await raid(tester);
      await tester.tap(find.byKey(const ValueKey('raid-start')));
      await tester.pump(const Duration(milliseconds: 50));
      final world =
          (tester.state(find.byType(RayRaidGame)) as dynamic).world
              as RayRaidWorld;
      final dash = tester
          .widget<RaidAbilityButton>(find.byKey(const ValueKey('raid-dash')))
          .onPressed;
      final nav = Navigator.of(tester.element(find.byType(RayRaidPage)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Важный экран')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final time = world.elapsed;
      dash();
      await tester.pump(const Duration(seconds: 2));
      expect(world.paused, true);
      expect(world.elapsed, time);
      expect(world.dashUses, 0);
      expect(find.text('Важный экран'), findsOneWidget);
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('raid-resume')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('raid-resume')));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Вернуться на корабль?'), findsOneWidget);
      final exit = tester
          .widget<FilledButton>(find.byKey(const ValueKey('raid-exit')))
          .onPressed!;
      await tester.tap(find.byKey(const ValueKey('raid-exit')));
      await tester.pumpAndSettle();
      exit();
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryPage), findsOneWidget);
      expect(repo.writes, isEmpty);
      expect(controller.completedCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final style in ['blocks', 'squad', 'comic', 'workshop', 'islands']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '$style narrow map and final stop remain reachable at scale $scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          gameDesign.value = GameDesign.byId(style);
          repo.play['confirmed_total'] = 160;
          repo.publish();
          await mount(tester, scale: scale);
          await stop(tester, 'shipyard-crew');
          final answer = find.byKey(
            ValueKey('discovery-answer-${spaceDiscoveries.last.answer}'),
          );
          await reveal(tester, answer);
          await tester.tap(answer);
          await tester.pumpAndSettle();
          await reveal(
            tester,
            find.byKey(const ValueKey('discovery-feedback')),
          );
          expect(find.textContaining('Верно!'), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(repo.writes, isEmpty);
        },
      );
    }
  }
}
