import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/robot_workshop_game.dart';
import 'package:mykids_family/engagement/space_memory_game.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  final oldDesign = gameDesign.value;
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDown(() => gameDesign.value = oldDesign);

  Future<void> mount(
    WidgetTester tester, {
    bool workshop = false,
    int level = 0,
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
              if (workshop)
                RobotWorkshopGame(
                  key: const ValueKey('test-workshop'),
                  challenge: robotWorkshopChallenges[level],
                  canPlay: canPlay ?? () => true,
                )
              else
                SpaceMemoryGame(
                  key: const ValueKey('test-pairs'),
                  challenge: spaceMemoryChallenges[level],
                  canPlay: canPlay ?? () => true,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder.hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<List<String>> peekCards(WidgetTester tester) async {
    await tap(tester, 'memory-peek');
    final cards = [
      for (var i = 0; i < 6; i++)
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(ValueKey('memory-card-$i')),
                matching: find.byType(Text),
              ),
            )
            .data!,
    ];
    expect(cards.toSet(), hasLength(3));
    await tap(tester, 'memory-peek');
    return cards;
  }

  Future<void> solvePairs(WidgetTester tester, int level) async {
    final cards = await peekCards(tester);
    for (final symbol in cards.toSet()) {
      for (var index = 0; index < cards.length; index++) {
        if (cards[index] == symbol) await tap(tester, 'memory-card-$index');
      }
    }
    expect(find.text('Найдено пар: 3 из 3'), findsOneWidget);
    expect(find.textContaining('Все пары найдены!'), findsOneWidget);
  }

  Future<void> buildRobot(WidgetTester tester, int level) async {
    for (final step in robotWorkshopChallenges[level].steps) {
      await tap(tester, 'workshop-part-${step.answer.name}');
    }
    expect(find.text('Детали робота: 3 из 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('workshop-question')), findsNothing);
    expect(find.text(robotWorkshopChallenges[level].ending), findsOneWidget);
  }

  test('all memory sets have three distinct complete pairs', () {
    expect(spaceMemoryChallenges.map((c) => c.id).toSet(), hasLength(3));
    for (final challenge in spaceMemoryChallenges) {
      expect(challenge.cards, hasLength(6));
      expect(challenge.cards.toSet(), hasLength(3));
      for (final card in challenge.cards.toSet()) {
        expect(challenge.cards.where((c) => c == card), hasLength(2));
      }
    }
  });
  test(
    'each workshop stage has one valid answer among three distinct parts',
    () {
      expect(robotWorkshopChallenges.map((c) => c.id).toSet(), hasLength(3));
      for (final challenge in robotWorkshopChallenges) {
        expect(challenge.steps, hasLength(3));
        for (final step in challenge.steps) {
          expect(step.choices.toSet(), hasLength(3));
          expect(step.choices.where((p) => p == step.answer), hasLength(1));
          expect(step.hint, isNotEmpty);
        }
      }
    },
  );
  for (var level = 0; level < 3; level++) {
    testWidgets('pairs $level completes and replays', (tester) async {
      await mount(tester, level: level);
      await solvePairs(tester, level);
      await tap(tester, 'memory-restart');
      expect(find.text('Найдено пар: 0 из 3'), findsOneWidget);
      expect(find.textContaining('Все пары найдены!'), findsNothing);
      await solvePairs(tester, level);
    });
    testWidgets('workshop $level completes and replays', (tester) async {
      await mount(tester, workshop: true, level: level);
      await buildRobot(tester, level);
      await tap(tester, 'workshop-restart');
      expect(find.text('Детали робота: 0 из 3'), findsOneWidget);
      await buildRobot(tester, level);
    });
  }
  testWidgets(
    'different cards stay visible until explicit retry; peek is free',
    (tester) async {
      await mount(tester);
      final cards = await peekCards(tester);
      final other = cards.indexWhere((c) => c != cards.first);
      await tap(tester, 'memory-card-0');
      await tap(tester, 'memory-card-$other');
      expect(find.textContaining('Карточки разные.'), findsOneWidget);
      expect(find.text('Найдено пар: 0 из 3'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('memory-card-2')))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(hours: 3));
      expect(find.text(cards.first), findsOneWidget);
      expect(find.text(cards[other]), findsOneWidget);
      await tap(tester, 'memory-peek');
      expect(find.text('Робот'), findsNWidgets(2));
      await tap(tester, 'memory-peek');
      await tap(tester, 'memory-next');
      expect(find.text('Звезда'), findsNothing);
      await solvePairs(tester, 0);
    },
  );
  testWidgets(
    'same open card cannot match itself; stale round callbacks do nothing',
    (tester) async {
      await mount(tester);
      final oldCard = tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('memory-card-0')))
          .onPressed!;
      await tap(tester, 'memory-card-0');
      oldCard();
      await tester.pumpAndSettle();
      expect(find.text('Найдено пар: 0 из 3'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('memory-card-0')))
            .onPressed,
        isNull,
      );
      final previousRound = tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('memory-card-3')))
          .onPressed!;
      await tap(tester, 'memory-restart');
      previousRound();
      await tester.pumpAndSettle();
      expect(find.text('Звезда'), findsNothing);
      await solvePairs(tester, 0);
    },
  );
  testWidgets('wrong part keeps current step and shows a useful hint', (
    tester,
  ) async {
    await mount(tester, workshop: true);
    await tap(tester, 'workshop-part-fins');
    expect(find.text('Детали робота: 0 из 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('workshop-hint')), findsOneWidget);
    final old = tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('workshop-part-wheels')),
        )
        .onPressed!;
    await tap(tester, 'workshop-part-wheels');
    old();
    await tester.pumpAndSettle();
    expect(find.text('Детали робота: 1 из 3'), findsOneWidget);
    await tap(tester, 'workshop-restart');
    old();
    await tester.pumpAndSettle();
    expect(find.text('Детали робота: 0 из 3'), findsOneWidget);
    await buildRobot(tester, 0);
  });
  for (final workshop in [false, true]) {
    testWidgets(
      '${workshop ? 'workshop' : 'pairs'} revokes moves, hints and reset immediately',
      (tester) async {
        var allowed = true;
        await mount(tester, workshop: workshop, canPlay: () => allowed);
        final actionKey = workshop ? 'workshop-part-wheels' : 'memory-card-0';
        final action = tester
            .widget<OutlinedButton>(find.byKey(ValueKey(actionKey)))
            .onPressed!;
        final hint = tester
            .widget<TextButton>(
              find.byKey(
                ValueKey(workshop ? 'workshop-show-hint' : 'memory-peek'),
              ),
            )
            .onPressed!;
        final restart = tester
            .widget<OutlinedButton>(
              find.byKey(
                ValueKey(workshop ? 'workshop-restart' : 'memory-restart'),
              ),
            )
            .onPressed!;
        allowed = false;
        action();
        hint();
        restart();
        await tester.pumpAndSettle();
        expect(
          find.text(workshop ? 'Детали робота: 0 из 3' : 'Найдено пар: 0 из 3'),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey(workshop ? 'workshop-hint' : 'memory-feedback')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        action();
        hint();
        restart();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${workshop ? 'workshop' : 'pairs'} rejects callbacks after challenge replacement',
      (tester) async {
        await mount(tester, workshop: workshop);
        final key = workshop ? 'workshop-part-wheels' : 'memory-card-0';
        final old = tester
            .widget<OutlinedButton>(find.byKey(ValueKey(key)))
            .onPressed!;
        await mount(tester, workshop: workshop, level: 1);
        old();
        await tester.pumpAndSettle();
        expect(
          find.text(workshop ? 'Детали робота: 0 из 3' : 'Найдено пар: 0 из 3'),
          findsOneWidget,
        );
        if (workshop) {
          await buildRobot(tester, 1);
        } else {
          await solvePairs(tester, 1);
        }
      },
    );
  }
  testWidgets(
    'closed cards have numbered accessible tap actions without disclosing symbols',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(tester);
        final node = tester.getSemantics(
          find.byKey(const ValueKey('memory-card-semantics-0')),
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
        expect(node.label, contains('Карточка 1: закрыта'));
        expect(node.label, isNot(contains('Звезда')));
        await tap(tester, 'memory-card-0');
        expect(
          tester
              .getSemantics(
                find.byKey(const ValueKey('memory-card-semantics-0')),
              )
              .label,
          isNot(contains('закрыта')),
        );
      } finally {
        semantics.dispose();
      }
    },
  );
  for (final style in ['squad', 'blocks', 'comic', 'workshop', 'islands']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$style all six games fit320x568 at text scale$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        gameDesign.value = GameDesign.byId(style);
        for (var level = 0; level < 3; level++) {
          await mount(tester, level: level, scale: scale);
          final size = tester.getSize(
            find.byKey(const ValueKey('memory-card-0')),
          );
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
          await tap(tester, 'memory-peek');
          await tap(tester, 'memory-peek');
          await solvePairs(tester, level);
          await mount(tester, workshop: true, level: level, scale: scale);
          await tap(tester, 'workshop-show-hint');
          await buildRobot(tester, level);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}
