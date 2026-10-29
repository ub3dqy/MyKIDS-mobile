import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/visuals.dart';
import 'package:record/record.dart';

import 'support/owned_temp.dart';
import 'voice_message_safety_test.dart'
    show VoiceFixture, VoicePlatform, VoicePlayer;

class ExitPlayer extends VoicePlayer {
  Completer<void>? stopGate;

  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late RecordPlatform original;
  late VoicePlatform capture;
  late VoiceFixture repo;
  late ExitPlayer player;
  late ValueNotifier<VoiceFixture> selection;
  late GlobalKey<NavigatorState> navigator;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('mykids-chat-exit-');
    original = RecordPlatform.instance;
    capture = VoicePlatform();
    RecordPlatform.instance = capture;
    repo = VoiceFixture()..folder = folder;
    player = ExitPlayer();
    selection = ValueNotifier(repo);
    navigator = GlobalKey<NavigatorState>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => folder.path,
        );
  });

  Future<void> io(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    bool large = false,
    ThemeData? theme,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() async {
      if (player.stopGate?.isCompleted == false) player.stopGate!.complete();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await io(tester);
      for (final item in {repo, selection.value}) {
        item.client.close();
        item.dispose();
      }
      selection.dispose();
      RecordPlatform.instance = original;
      await capture.states.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await deleteOwnedTestTemp(folder);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        navigatorKey: navigator,
        builder: large
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              )
            : null,
        home: const Scaffold(body: Text('Список семейных чатов')),
      ),
    );
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ValueListenableBuilder<VoiceFixture>(
            valueListenable: selection,
            builder: (_, owner, _) => ChatScreen(
              repository: owner,
              room: owner
                  .rows('rooms')
                  .firstWhere((room) => room['kind'] == 'private'),
              audioPlayer: player,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> draft(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Голосовое'));
    await io(tester);
    expect(capture.capturing, true);
    await tester.tap(find.byTooltip('Остановить запись'));
    await io(tester);
    expect(find.text('Запись готова'), findsOneWidget);
    expect(File(capture.path!).existsSync(), true);
    return capture.path!;
  }

  void queuedBack(WidgetTester tester) {
    tester
        .widget<PopScope<void>>(find.byType(PopScope<void>))
        .onPopInvokedWithResult!(false, null);
  }

  Future<void> decision(WidgetTester tester) async {
    await navigator.currentState!.maybePop();
    await io(tester);
    await tester.pumpAndSettle();
    expect(find.text('Удалить голосовую запись?'), findsOneWidget);
  }

  Future<void> cover(WidgetTester tester) async {
    unawaited(
      navigator.currentState!.push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) =>
              const Scaffold(body: Text('Важный экран поверх чата')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await io(tester);
  }

  for (final label in ['Остаться', 'Удалить и выйти']) {
    testWidgets('retained voice decision $label preserves a covering screen', (
      tester,
    ) async {
      await mount(tester);
      final path = await draft(tester);
      await decision(tester);
      final callback = tester
          .widget<TextButton>(find.widgetWithText(TextButton, label))
          .onPressed!;
      await cover(tester);
      callback();
      await io(tester);
      await tester.pumpAndSettle();
      expect(find.text('Важный экран поверх чата'), findsOneWidget);
      expect(File(path).existsSync(), true);
      navigator.currentState!.pop(false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Остаться'));
      await tester.pumpAndSettle();
      expect(find.text('Запись готова'), findsOneWidget);
      expect(repo.uploads, 0);
      expect(repo.voiceMessages, 0);
    });
  }

  for (final recording in [false, true]) {
    testWidgets('late chat exit keeps a new covering route; draft=$recording', (
      tester,
    ) async {
      await mount(tester);
      final path = recording ? await draft(tester) : null;
      player.stopGate = Completer<void>();
      queuedBack(tester);
      await tester.pump();
      await cover(tester);
      player.stopGate!.complete();
      await io(tester);
      await tester.pumpAndSettle();
      expect(find.text('Важный экран поверх чата'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      if (path != null) expect(File(path).existsSync(), true);
      expect(repo.uploads, 0);
      expect(repo.voiceMessages, 0);
    });
  }

  testWidgets('queued Back on an already covered chat does nothing', (
    tester,
  ) async {
    await mount(tester);
    final path = await draft(tester);
    final back = tester
        .widget<PopScope<void>>(find.byType(PopScope<void>))
        .onPopInvokedWithResult!;
    await cover(tester);
    final stops = player.stops;
    back(false, null);
    await io(tester);
    await tester.pumpAndSettle();
    expect(find.text('Важный экран поверх чата'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(player.stops, stops);
    expect(File(path).existsSync(), true);
  });

  testWidgets('a new cover after approval prevents late deletion and exit', (
    tester,
  ) async {
    await mount(tester);
    final path = await draft(tester);
    await decision(tester);
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Удалить и выйти'))
        .onPressed!();
    await cover(tester);
    await io(tester);
    await tester.pumpAndSettle();
    expect(find.text('Важный экран поверх чата'), findsOneWidget);
    expect(File(path).existsSync(), true);
    expect(repo.uploads, 0);
  });

  for (final replace in [false, true]) {
    testWidgets('obsolete voice decision is masked; repository=$replace', (
      tester,
    ) async {
      await mount(tester);
      await draft(tester);
      await decision(tester);
      final approve = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Удалить и выйти'),
          )
          .onPressed!;
      if (replace) {
        selection.value = VoiceFixture()..folder = folder;
      } else {
        repo.token = 'synthetic-replaced-chat-owner';
        repo.generation++;
        repo.notifyListeners();
      }
      await io(tester);
      await tester.pumpAndSettle();
      approve();
      await io(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Нужно открыть окно заново'), findsOneWidget);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.text('Чат недоступен'), findsOneWidget);
      expect(repo.uploads, 0);
      expect(selection.value.uploads, 0);
    });
  }

  for (final online in [false, true]) {
    testWidgets('current draft can be kept and deleted; online=$online', (
      tester,
    ) async {
      await mount(tester);
      final path = await draft(tester);
      repo.online = online;
      repo.notifyListeners();
      await decision(tester);
      await tester.tap(find.text('Остаться'));
      await tester.pumpAndSettle();
      expect(File(path).existsSync(), true);
      expect(find.text('Запись готова'), findsOneWidget);
      await decision(tester);
      await tester.tap(find.text('Удалить и выйти'));
      await tester.pumpAndSettle();
      await io(tester);
      await tester.pumpAndSettle();
      expect(find.text('Список семейных чатов'), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(File(path).existsSync(), false);
      expect(repo.uploads, 0);
      expect(repo.voiceMessages, 0);
    });
  }

  testWidgets('voice discard decision fits a short screen with 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, large: true);
    await draft(tester);
    await decision(tester);
    expect(tester.takeException(), isNull);
    final button = find.widgetWithText(TextButton, 'Остаться');
    await tester.ensureVisible(button);
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Запись готова'), findsOneWidget);
  });

  for (final design in GameDesign.all) {
    testWidgets('chat title keeps readable contrast in ${design.id}', (
      tester,
    ) async {
      gameDesign.value = design;
      addTearDown(() => gameDesign.value = null);
      await mount(tester, theme: familyTheme(false));
      final title = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Папа'),
      );
      expect(title, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(title);
      final foreground = paragraph.text.style!.color!;
      final background = tester
          .widget<AppBar>(find.byType(AppBar))
          .backgroundColor!;
      final a = foreground.computeLuminance(),
          b = background.computeLuminance();
      expect(
        (math.max(a, b) + .05) / (math.min(a, b) + .05),
        greaterThanOrEqualTo(4.5),
      );
      expect(paragraph.size.width, greaterThan(20));
      expect(tester.takeException(), isNull);
    });
  }
}
