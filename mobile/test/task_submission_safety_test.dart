import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'submission_photos_test.dart' show PhotoFixture, tapPhotoPicker;

class SlowPhotoCopy extends PhotoFixture {
  final copied = Completer<void>();
  final releaseCopy = Completer<void>();
  SlowPhotoCopy() : super(minimum: 1);
  @override
  Future<String> keepFile(String source) async {
    final path = await super.keepFile(source);
    copied.complete();
    await releaseCopy.future;
    return path;
  }
}

Future<void> openSubmission(
  WidgetTester tester,
  PhotoFixture repo, {
  Future<List<String>> Function(int)? picker,
  ValueNotifier<PhotoFixture>? selection,
  Future<void> Function(Future<Map<String, dynamic>> Function())? perform,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(repo.prepare);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(repo.closePhotos);
    repo.client.close();
    repo.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: selection ?? repo,
          builder: (_, _) => TaskScreen(
            repository: selection?.value ?? repo,
            focusTaskId: 'task',
            selectPhotos: picker ?? (_) async => [],
            perform:
                perform ??
                (action) async {
                  await action();
                },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Две страницы математики'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Готово — отправить на проверку'));
  await tester.tap(find.text('Готово — отправить на проверку'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  final source = File('assets/generated/calendar-task.png').absolute.path;

  testWidgets(
    'selected task is immediately reachable on a short large-text screen',
    (tester) async {
      final repo = PhotoFixture(minimum: 0);
      final previousDesign = gameDesign.value;
      gameDesign.value = GameDesign.byId('squad');
      tester.view.physicalSize = const Size(640, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        gameDesign.value = previousDesign;
        repo.client.close();
        repo.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: TaskScreen(
              repository: repo,
              focusTaskId: 'task',
              perform: (_) async =>
                  fail('Opening and cancelling must not send a result'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text('Две страницы математики');
      expect(title.hitTestable(), findsOneWidget);
      await tester.tap(title);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Готово — отправить на проверку'),
        120,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Готово — отправить на проверку')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Готово — отправить на проверку').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Готово — отправить на проверку'));
      await tester.pumpAndSettle();
      expect(find.text('Отправить результат'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(repo.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final change in [
    'session',
    'endpoint',
    'generation',
    'temporary-role',
  ]) {
    testWidgets('submission masks the old draft after $change changes', (
      tester,
    ) async {
      final repo = PhotoFixture(minimum: 0);
      await openSubmission(tester, repo);
      await tester.enterText(
        find.byType(TextField),
        'Личный комментарий ребёнка',
      );
      final send = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Отправить на проверку'),
          )
          .onPressed!;
      switch (change) {
        case 'session':
          repo.token = 'different-synthetic-session';
        case 'endpoint':
          repo.endpoint = 'https://other.invalid';
        case 'generation':
          repo.generation++;
        case 'temporary-role':
          repo.snapshot!['user']['role'] = 'parent';
          repo.notifyListeners();
          repo.snapshot!['user']['role'] = 'child';
      }
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Личный комментарий ребёнка'), findsNothing);
      expect(find.text('Нужно открыть окно заново'), findsOneWidget);
      send();
      await tester.pumpAndSettle();
      expect(repo.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('old submission cancel cannot close a covering route', (
    tester,
  ) async {
    final repo = PhotoFixture(minimum: 0);
    await openSubmission(tester, repo);
    final cancel = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Отмена'))
        .onPressed!;
    final navigator = Navigator.of(tester.element(find.byType(AlertDialog)));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Другой экран')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    cancel();
    await tester.pumpAndSettle();
    expect(find.text('Другой экран'), findsOneWidget);
    expect(repo.mutations, isEmpty);
  });

  testWidgets('rapid submission entry opens one window', (tester) async {
    final repo = PhotoFixture(minimum: 0);
    await openSubmission(tester, repo);
    final entry = tester
        .widget<FilledButton>(
          find.widgetWithText(
            FilledButton,
            'Готово — отправить на проверку',
            skipOffstage: false,
          ),
        )
        .onPressed!;
    entry();
    entry();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    expect(repo.mutations, isEmpty);
  });

  testWidgets('replacement repository hides old draft with the same child id', (
    tester,
  ) async {
    final first = PhotoFixture(minimum: 0), second = PhotoFixture(minimum: 0);
    final selection = ValueNotifier(first);
    addTearDown(() {
      selection.dispose();
      second.client.close();
      second.dispose();
    });
    await openSubmission(tester, first, selection: selection);
    await tester.enterText(find.byType(TextField), 'Старый личный текст');
    selection.value = second;
    await tester.pumpAndSettle();
    expect(find.text('Старый личный текст'), findsNothing);
    expect(find.text('Нужно открыть окно заново'), findsOneWidget);
    expect(first.mutations, isEmpty);
    expect(second.mutations, isEmpty);
  });

  testWidgets('offline submission keeps the comment and queues once', (
    tester,
  ) async {
    final repo = PhotoFixture(minimum: 0)..online = false;
    await openSubmission(tester, repo);
    await tester.enterText(find.byType(TextField), 'Готово без связи');
    final send = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Отправить на проверку'),
        )
        .onPressed!;
    send();
    send();
    await tester.pumpAndSettle();
    expect(repo.mutations, hasLength(1));
    expect(repo.mutations.single['note'], 'Готово без связи');
    expect(repo.mutations.single['offlineSubmission'], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled picker neither copies nor sends a late selection', (
    tester,
  ) async {
    final picked = Completer<List<String>>();
    final repo = PhotoFixture(minimum: 1);
    await openSubmission(tester, repo, picker: (_) => picked.future);
    await tester.ensureVisible(find.text('Добавить фото'));
    await tester.tap(find.text('Добавить фото'));
    await tester.pump();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    picked.complete([source]);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(repo.sequence, 0);
    expect(repo.photoFolder.listSync(), isEmpty);
    expect(repo.mutations, isEmpty);
    expect(File(source).existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected local copies are deleted on cancel, gallery originals stay',
    (tester) async {
      final repo = PhotoFixture(minimum: 1);
      await openSubmission(tester, repo, picker: (_) async => [source]);
      await tapPhotoPicker(tester);
      expect(repo.photoFolder.listSync(), hasLength(1));
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(repo.photoFolder.listSync(), isEmpty);
      expect(File(source).existsSync(), isTrue);
      expect(repo.mutations, isEmpty);
    },
  );

  testWidgets('cancelling during a private copy deletes the late file', (
    tester,
  ) async {
    final repo = SlowPhotoCopy();
    await openSubmission(tester, repo, picker: (_) async => [source]);
    await tester.ensureVisible(find.text('Добавить фото'));
    await tester.tap(find.text('Добавить фото'));
    addTearDown(() {
      if (!repo.releaseCopy.isCompleted) repo.releaseCopy.complete();
    });
    for (var attempt = 0; attempt < 40 && !repo.copied.isCompleted; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    expect(repo.copied.isCompleted, isTrue);
    await tester.pump();
    expect(repo.photoFolder.listSync(), hasLength(1));
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    repo.releaseCopy.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(repo.photoFolder.listSync(), isEmpty);
    expect(repo.mutations, isEmpty);
    expect(File(source).existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing access while picking does not keep another session photo',
    (tester) async {
      final picked = Completer<List<String>>();
      final repo = PhotoFixture(minimum: 1);
      await openSubmission(tester, repo, picker: (_) => picked.future);
      await tester.ensureVisible(find.text('Добавить фото'));
      await tester.tap(find.text('Добавить фото'));
      await tester.pump();
      repo.generation++;
      repo.notifyListeners();
      picked.complete([source]);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Нужно открыть окно заново'), findsOneWidget);
      expect(repo.sequence, 0);
      expect(repo.photoFolder.listSync(), isEmpty);
      expect(repo.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale entry callback cannot open for a new session', (
    tester,
  ) async {
    final repo = PhotoFixture(minimum: 0);
    await openSubmission(tester, repo);
    final entry = tester
        .widget<FilledButton>(
          find.widgetWithText(
            FilledButton,
            'Готово — отправить на проверку',
            skipOffstage: false,
          ),
        )
        .onPressed!;
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    repo.generation++;
    entry();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.mutations, isEmpty);
  });

  testWidgets(
    'submission remains scrollable on a short screen with large text',
    (tester) async {
      final repo = PhotoFixture(minimum: 0);
      await openSubmission(tester, repo);
      tester.view.physicalSize = const Size(640, 320);
      final context = tester.element(find.byType(AlertDialog));
      // Change the actual platform accessibility setting and let MediaQuery update.
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Отправить на проверку')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Отправить на проверку').hitTestable(), findsOneWidget);
      expect(context.mounted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
