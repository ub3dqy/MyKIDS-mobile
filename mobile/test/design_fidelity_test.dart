import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_review_repository.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/school_screen.dart';
import 'package:mykids_family/visuals.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PendingDesignRepository extends DesignReviewRepository {
  List<Map<String, Object?>> changes = [];
  @override
  Future<List<Map<String, Object?>>> pending() async => changes;
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
  });
  tearDown(() => gameDesign.value = null);

  testWidgets('a mounted constant logo follows every live world transition', (
    tester,
  ) async {
    for (final initial in GameDesign.all) {
      gameDesign.value = initial;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(home: const Scaffold(body: FamilyLogo(width: 96))),
      );
      for (final selected in GameDesign.all) {
        gameDesign.value = selected;
        await tester.pump();
        final logo = tester.widget<Text>(find.text('MyKIDS'));
        expect(
          logo.style!.color,
          selected.onHeader,
          reason: '${initial.id} → ${selected.id} without restarting',
        );
        expect(tester.getSize(find.byType(FamilyLogo)).width, 96);
      }
    }
  });

  for (final design in GameDesign.all) {
    testWidgets('${design.id}: empty sync queue adds no calendar space', (
      tester,
    ) async {
      gameDesign.value = design;
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = PendingDesignRepository();
      addTearDown(() {
        repo.client.close();
        repo.dispose();
      });
      Widget calendar() => MaterialApp(
        theme: design.theme(true),
        home: Scaffold(
          body: CalendarScreen(
            key: UniqueKey(),
            repository: repo,
            perform: (action) async {
              await action();
            },
            openTasks: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(calendar());
      await tester.pump();
      final approvedTop = tester.getTopLeft(find.text('День')).dy;
      sqfliteFfiInit();
      final database = (await tester.runAsync(
        () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
      ))!;
      addTearDown(database.close);
      repo.db = database;
      await tester.pumpWidget(calendar());
      await tester.pump();
      expect(tester.getTopLeft(find.text('День')).dy, approvedTop);
      repo.changes = [
        {'path': '/v1/schedules', 'state': 'failed', 'error': 'Проверь время'},
      ];
      await tester.pumpWidget(calendar());
      await tester.pump();
      expect(
        find.textContaining('Изменений ожидают сверки: 1'),
        findsOneWidget,
      );
      expect(
        find.text('Изменение не применено: Проверь время'),
        findsOneWidget,
      );
      expect(tester.getTopLeft(find.text('День')).dy, greaterThan(approvedTop));
      expect(tester.takeException(), isNull);
    });
    testWidgets('${design.id}: reward request returns to the updated balance', (
      tester,
    ) async {
      gameDesign.value = design;
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 52, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 52, bottom: 24);
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DesignReviewRepository();
      addTearDown(() {
        repo.client.close();
        repo.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: design.theme(true),
          home: Scaffold(
            body: AnimatedBuilder(
              animation: repo,
              builder: (_, _) => MoneyScreen(
                repository: repo,
                perform: (action) async {
                  await action();
                },
              ),
            ),
          ),
        ),
      );
      final reward = find.byKey(const ValueKey('reward-picnic'));
      final title = find.text('Пикник всей семьёй · 100 монет');
      await tester.scrollUntilVisible(title, 250, maxScrolls: 20);
      await tester.ensureVisible(title);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(title);
      await tester.pump(const Duration(milliseconds: 400));
      final request = find.descendant(
        of: reward,
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(request);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(request);
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.snapshot!['balance']['available'], 25);
      expect(repo.snapshot!['balance']['reserved'], 100);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.pixels, 0);
      expect(
        find.text('Доступно для твоих желаний').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    for (final role in ['child', 'parent']) {
      testWidgets('${design.id}: $role grades keep the approved bare layout', (
        tester,
      ) async {
        gameDesign.value = design;
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 52, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 52, bottom: 24);
        addTearDown(tester.view.reset);
        final repo = DesignReviewRepository()..switchRole(role);
        addTearDown(() {
          repo.client.close();
          repo.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: design.theme(role == 'child'),
            home: SchoolScreen(
              repository: repo,
              gradesOnly: true,
              initialDay: DateTime.parse(
                repo.snapshot!['grades'].first['date'],
              ),
              perform: (action) async {
                await action();
              },
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(AppBar), findsNothing);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('results-date'))).dy,
          64,
        );
        final history = find.text('Сохранённые оценки');
        await tester.scrollUntilVisible(
          history,
          250,
          maxScrolls: 30,
          scrollable: find.byType(Scrollable),
        );
        expect(history.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
