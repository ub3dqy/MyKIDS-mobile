import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/task_photo_viewer.dart';

import 'task_rules_test.dart' show TaskFixture;

Future<void> waitForPhoto(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    final image = find.byType(RawImage);
    if (image.evaluate().isNotEmpty &&
        tester.widget<RawImage>(image.first).image != null) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

TransformationController photoTransform(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byKey(const ValueKey('task-photo-zoom')))
    .transformationController!;

Future<void> openViewer(
  WidgetTester tester,
  TaskFixture repository,
  List<Future<File> Function()> photos, {
  int initialIndex = 0,
  double textScale = 1,
}) async {
  addTearDown(() {
    repository.client.close();
    repository.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => TaskPhotoViewer(
                  repository: repository,
                  photos: photos,
                  initialIndex: initialIndex,
                ),
              ),
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  // A pending download intentionally keeps the progress indicator animating.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  final source = File('assets/generated/calendar-task.png').absolute;

  testWidgets(
    'double tap zooms at the touched point, pan moves and reset fits',
    (tester) async {
      await openViewer(tester, TaskFixture(), [() async => source]);
      await waitForPhoto(tester);
      final viewport = find.byKey(const ValueKey('task-photo-zoom'));
      final box = tester.getRect(viewport);
      final point = box.topLeft + Offset(box.width * .35, box.height * .45);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      final controller = photoTransform(tester);
      expect(controller.value.getMaxScaleOnAxis(), closeTo(3, .001));
      final scene = controller.toScene(point - box.topLeft);
      expect(scene.dx, closeTo(box.width * .35, .001));
      expect(scene.dy, closeTo(box.height * .45, .001));
      final beforePan = controller.value.clone();
      await tester.drag(viewport, const Offset(-80, -100));
      await tester.pumpAndSettle();
      expect(controller.value, isNot(beforePan));
      await tester.tap(find.byTooltip('Показать целиком'));
      await tester.pumpAndSettle();
      expect(controller.value, Matrix4.identity());
      await tester.tap(find.byTooltip('Закрыть фотографию'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskPhotoViewer), findsNothing);
      expect(find.text('Открыть'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('two fingers zoom and buttons stay within supported limits', (
    tester,
  ) async {
    await openViewer(tester, TaskFixture(), [() async => source]);
    await waitForPhoto(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);
    await first.down(center - const Offset(40, 0));
    await second.down(center + const Offset(40, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(80, 0));
    await second.moveTo(center + const Offset(80, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(120, 0));
    await second.moveTo(center + const Offset(120, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    final controller = photoTransform(tester);
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.4));
    for (var tap = 0; tap < 12; tap++) {
      await tester.tap(find.byTooltip('Увеличить'));
      await tester.pump();
    }
    expect(controller.value.getMaxScaleOnAxis(), 8);
    for (var tap = 0; tap < 12; tap++) {
      await tester.tap(find.byTooltip('Уменьшить'));
      await tester.pump();
    }
    expect(controller.value, Matrix4.identity());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opens the chosen page, loads lazily and resets zoom on next page',
    (tester) async {
      final calls = <int>[];
      final repository = TaskFixture();
      await openViewer(tester, repository, [
        for (var index = 0; index < 3; index++)
          () async {
            calls.add(index);
            return source;
          },
      ], initialIndex: 1);
      await waitForPhoto(tester);
      expect(calls, [1]);
      expect(find.text('Фото 2 из 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Увеличить'));
      await tester.pump();
      await tester.tap(find.byTooltip('Следующее фото'));
      await waitForPhoto(tester);
      expect(calls, [1, 2]);
      expect(find.text('Фото 3 из 3'), findsOneWidget);
      expect(photoTransform(tester).value, Matrix4.identity());
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Следующее фото'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Предыдущее фото'));
      await waitForPhoto(tester);
      expect(calls, [1, 2]);
      expect(repository.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'download failure can retry and a broken image has a clear error',
    (tester) async {
      var attempts = 0;
      await openViewer(tester, TaskFixture(), [
        () async {
          if (attempts++ == 0) throw const FileSystemException('private path');
          return source;
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Не удалось открыть фотографию'), findsOneWidget);
      expect(find.textContaining('private path'), findsNothing);
      await tester.tap(find.text('Повторить'));
      await waitForPhoto(tester);
      expect(attempts, 2);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть фотографию'));
      await tester.pumpAndSettle();
      await openViewer(tester, TaskFixture(), [
        () async => File('assets/generated/does-not-exist.png'),
      ]);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Не удалось открыть фотографию'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final pending in [false, true]) {
    testWidgets('session switch closes ${pending ? 'loading' : 'open'} photo', (
      tester,
    ) async {
      final repository = TaskFixture();
      final download = Completer<File>();
      await openViewer(tester, repository, [
        pending ? () => download.future : () async => source,
      ]);
      if (!pending) await waitForPhoto(tester);
      repository.generation++;
      repository.token = 'different-session';
      repository.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(TaskPhotoViewer), findsNothing);
      if (pending) {
        download.complete(source);
        await tester.pumpAndSettle();
      }
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('controls fit a narrow screen, large text and landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openViewer(tester, TaskFixture(), [
      () async => source,
      () async => source,
    ], textScale: 2);
    await waitForPhoto(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Увеличить'));
    await tester.pump();
    tester.view.physicalSize = const Size(640, 320);
    await tester.pumpAndSettle();
    expect(photoTransform(tester).value, Matrix4.identity());
    expect(
      tester.getSize(find.byType(InteractiveViewer)).height,
      greaterThan(0),
    );
    await tester.tap(find.byTooltip('Следующее фото'));
    await waitForPhoto(tester);
    expect(find.text('Фото 2 из 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a session change before the viewer opens never loads the photo',
    (tester) async {
      final repository = TaskFixture();
      var loads = 0;
      final viewer = TaskPhotoViewer(
        repository: repository,
        photos: [
          () async {
            loads++;
            return source;
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                repository.generation++;
                Navigator.of(context)
                    .push<void>(MaterialPageRoute(builder: (_) => viewer));
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskPhotoViewer), findsNothing);
      expect(loads, 0);
      expect(tester.takeException(), isNull);
      repository.client.close();
      repository.dispose();
    },
  );

  testWidgets('fit remains full size during an unfinished pan animation', (
    tester,
  ) async {
    await openViewer(tester, TaskFixture(), [() async => source]);
    await waitForPhoto(tester);
    await tester.tap(find.byTooltip('Увеличить'));
    await tester.tap(find.byTooltip('Увеличить'));
    await tester.pump();
    await tester.fling(
      find.byType(InteractiveViewer),
      const Offset(-100, -80),
      1500,
    );
    await tester.tap(find.byTooltip('Показать целиком'));
    await tester.pump(const Duration(milliseconds: 300));
    final matrix = photoTransform(tester).value;
    expect(matrix.getMaxScaleOnAxis(), closeTo(1, .000001));
    expect(matrix.getTranslation().x, closeTo(0, .000001));
    expect(matrix.getTranslation().y, closeTo(0, .000001));
    expect(tester.takeException(), isNull);
  });
}
