import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/robot_route_game.dart';
import 'package:mykids_family/visuals.dart';

const routes = [
  [
    RobotDirection.up,
    RobotDirection.up,
    RobotDirection.up,
    RobotDirection.right,
    RobotDirection.right,
    RobotDirection.right,
  ],
  [
    RobotDirection.down,
    RobotDirection.down,
    RobotDirection.down,
    RobotDirection.right,
    RobotDirection.right,
    RobotDirection.right,
  ],
  [
    RobotDirection.left,
    RobotDirection.up,
    RobotDirection.up,
    RobotDirection.up,
    RobotDirection.left,
    RobotDirection.left,
  ],
];

void main() {
  final previousDesign = gameDesign.value;
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDown(() => gameDesign.value = previousDesign);

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      160,
      maxScrolls: 80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester, {
    int challenge = 0,
    double scale = 1,
    bool Function()? canPlay,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: familyTheme(true),
        builder: (_, child) => MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RobotRouteGame(
                key: const ValueKey('same-game'),
                challenge: robotRouteChallenges[challenge],
                canPlay: canPlay ?? () => true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (var index = 0; index < robotRouteChallenges.length; index++) {
    test('route $index has valid cells and its hint leads to the goal', () {
      final challenge = robotRouteChallenges[index];
      expect(challenge.size, inInclusiveRange(3, 5));
      expect(challenge.isOpen(challenge.start), true);
      expect(challenge.isOpen(challenge.goal), true);
      expect(challenge.start, isNot(challenge.goal));
      expect(challenge.walls.every(challenge.contains), true);
      var position = challenge.start;
      for (final direction in routes[index]) {
        final result = moveRobot(challenge, position, direction);
        expect([
          RobotMoveKind.moved,
          RobotMoveKind.arrived,
        ], contains(result.kind));
        expect(challenge.isOpen(result.cell), true);
        position = result.cell;
      }
      expect(position, challenge.goal);
      for (final direction in RobotDirection.values) {
        expect(moveRobot(challenge, position, direction).cell, challenge.goal);
      }
    });

    test('route $index never leaves open cells or enters an obstacle', () {
      final challenge = robotRouteChallenges[index];
      for (var row = 0; row < challenge.size; row++) {
        for (var column = 0; column < challenge.size; column++) {
          final start = (row: row, column: column);
          if (!challenge.isOpen(start)) continue;
          for (final direction in RobotDirection.values) {
            final result = moveRobot(challenge, start, direction);
            expect(challenge.isOpen(result.cell), true);
          }
        }
      }
    });
  }

  test('challenge identities are distinct', () {
    expect(robotRouteChallenges.map((c) => c.id).toSet(), hasLength(3));
  });

  testWidgets('edge, closed cell, hint, success and replay remain usable', (
    tester,
  ) async {
    await mount(tester);
    Future<void> tap(String key) async {
      final target = find.byKey(ValueKey(key));
      await reveal(tester, target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tap('robot-left');
    expect(find.textContaining('край площадки'), findsOneWidget);
    await tap('robot-right');
    await tap('robot-up');
    expect(find.textContaining('клетка закрыта'), findsOneWidget);
    await reveal(tester, find.text('Подсказка'));
    await tester.tap(find.text('Подсказка'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('robot-hint')), findsOneWidget);
    await tap('robot-restart');
    expect(find.byKey(const ValueKey('robot-hint')), findsNothing);
    for (final direction in routes[0]) {
      await tap('robot-${direction.name}');
    }
    expect(find.text(robotRouteChallenges.first.arrival), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('robot-up')))
          .onPressed,
      isNull,
    );
    await tap('robot-restart');
    expect(find.textContaining('Лучик: ряд 4, клетка 1.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoked and disposed callbacks cannot move or reset the robot', (
    tester,
  ) async {
    var allowed = true;
    await mount(tester, canPlay: () => allowed);
    final button = find.byKey(const ValueKey('robot-up'));
    await reveal(tester, button);
    final move = tester.widget<IconButton>(button).onPressed!;
    await reveal(tester, find.byKey(const ValueKey('robot-restart')));
    final reset = tester
        .widget<OutlinedButton>(find.byKey(const ValueKey('robot-restart')))
        .onPressed!;
    move();
    await tester.pumpAndSettle();
    expect(find.textContaining('Лучик: ряд 3, клетка 1.'), findsOneWidget);
    allowed = false;
    move();
    reset();
    await tester.pumpAndSettle();
    expect(find.textContaining('Лучик: ряд 3, клетка 1.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    move();
    reset();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a command from a replaced challenge cannot move the new challenge',
    (tester) async {
      await mount(tester);
      await reveal(tester, find.byKey(const ValueKey('robot-up')));
      final old = tester
          .widget<IconButton>(find.byKey(const ValueKey('robot-up')))
          .onPressed!;
      await mount(tester, challenge: 1);
      old();
      await tester.pumpAndSettle();
      expect(find.textContaining('Лучик: ряд 1, клетка 1.'), findsOneWidget);
      expect(find.byKey(const ValueKey('robot-feedback')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final style in ['blocks', 'squad', 'comic', 'workshop', 'islands']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$style robot controls fit a narrow screen at scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        gameDesign.value = GameDesign.byId(style);
        for (var index = 0; index < robotRouteChallenges.length; index++) {
          await mount(tester, challenge: index, scale: scale);
          for (final direction in routes[index]) {
            final control = find.byKey(ValueKey('robot-${direction.name}'));
            await reveal(tester, control);
            expect(
              tester.getSize(control).shortestSide,
              greaterThanOrEqualTo(48),
            );
            await tester.tap(control);
            await tester.pumpAndSettle();
          }
          expect(
            find.text(robotRouteChallenges[index].arrival),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
