import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_picker.dart';
import 'package:mykids_family/design_preferences.dart';
import 'package:mykids_family/design_review.dart'
    show ReviewBackground, ReviewUpdates;
import 'package:mykids_family/design_review_repository.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/design_today.dart';
import 'package:mykids_family/main.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
  });
  tearDown(() => gameDesign.value = null);

  test(
    'new, unknown and unreadable preferences use the approved default',
    () async {
      for (final read in <Future<String?> Function()>[
        () async => null,
        () async => 'unknown-future-world',
        () async => throw StateError('Storage unavailable'),
      ]) {
        var writes = 0;
        final prefs = DesignPreferences(
          read: read,
          write: (_) async => writes++,
        );
        await prefs.load();
        expect(gameDesign.value, same(GameDesign.all.first));
        expect(writes, 0);
      }
    },
  );

  test('all five choices survive a new preferences instance', () async {
    String? saved;
    final prefs = DesignPreferences(
      read: () async => saved,
      write: (id) async => saved = id,
    );
    for (final design in GameDesign.all) {
      await prefs.select(design);
      gameDesign.value = null;
      await DesignPreferences(
        read: () async => saved,
        write: (_) async {},
      ).load();
      expect(gameDesign.value, same(design));
    }
  });

  test(
    'queued saves keep order and a failed write keeps the previous design',
    () async {
      final first = Completer<void>();
      final calls = <String>[];
      gameDesign.value = GameDesign.all.first;
      final prefs = DesignPreferences(
        read: () async => null,
        write: (id) async {
          calls.add(id);
          if (calls.length == 1) await first.future;
        },
      );
      final failed = prefs.select(GameDesign.all[1]);
      final success = prefs.select(GameDesign.all[4]);
      final failure = expectLater(failed, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['squad']);
      expect(gameDesign.value!.id, 'blocks');
      first.completeError(StateError('Write failed'));
      await failure;
      await success;
      expect(calls, ['squad', 'islands']);
      expect(gameDesign.value!.id, 'islands');
    },
  );

  for (final role in ['child', 'parent', 'relative']) {
    testWidgets(
      '$role: choose all five in real settings, keep navigation and restart',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? saved;
        final prefs = DesignPreferences(
          read: () async => saved,
          write: (id) async => saved = id,
        );
        await prefs.load();
        final repo = DesignReviewRepository()..switchRole(role);
        addTearDown(() {
          repo.client.close();
          repo.dispose();
        });
        Widget application() => MyKidsApp(
          repository: repo,
          designPreferences: prefs,
          createBackground: ReviewBackground.new,
          createUpdates: ReviewUpdates.new,
        );
        await tester.pumpWidget(application());
        await frames(tester);
        await tester.tap(find.byTooltip('Настройки'));
        await frames(tester);
        await tester.tap(find.byKey(const ValueKey('appearance-settings')));
        await frames(tester);
        expect(find.byType(DesignPicker), findsOneWidget);
        for (final design in GameDesign.all) {
          final option = find.byKey(ValueKey('design-option-${design.id}'));
          await tester.scrollUntilVisible(option, 250, maxScrolls: 15);
          await tester.ensureVisible(option);
          await tester.tap(option);
          await frames(tester);
          expect(saved, design.id);
          expect(gameDesign.value, same(design));
          expect(tester.takeException(), isNull);
        }
        await tester.binding.handlePopRoute();
        await frames(tester);
        expect(
          find.byKey(const ValueKey('appearance-settings')),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Календарь').last);
        await frames(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Сегодня').last);
        await frames(tester);
        if (role == 'child') expect(find.byType(GameToday), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await frames(tester);
        gameDesign.value = null;
        await prefs.load();
        await tester.pumpWidget(application());
        await frames(tester);
        expect(gameDesign.value!.id, 'islands');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await frames(tester);
      },
    );
  }

  testWidgets('failed save is visible and can be retried with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var shouldFail = true;
    final prefs = DesignPreferences(
      read: () async => 'blocks',
      write: (_) async {
        if (shouldFail) throw StateError('No storage');
      },
    );
    await prefs.load();
    await tester.pumpWidget(
      ValueListenableBuilder<GameDesign?>(
        valueListenable: gameDesign,
        builder: (_, design, _) => MaterialApp(
          theme: design!.theme(true),
          home: DesignPicker(preferences: prefs),
        ),
      ),
    );
    await frames(tester);
    final option = find.byKey(const ValueKey('design-option-blocks'));
    await tester.tap(option);
    await frames(tester);
    expect(
      find.text('Не удалось запомнить выбор. Попробуй ещё раз.'),
      findsOneWidget,
    );
    expect(gameDesign.value!.id, 'blocks');
    shouldFail = false;
    await tester.ensureVisible(option);
    await tester.tap(option);
    await frames(tester);
    expect(
      find.text('Не удалось запомнить выбор. Попробуй ещё раз.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
