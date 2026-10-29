import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_photo_viewer.dart';

import 'task_photo_viewer_test.dart' show openViewer, waitForPhoto;
import 'task_rules_test.dart' show TaskFixture;

Finder photoButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

void main() {
  final source = File('assets/generated/calendar-task.png').absolute;

  testWidgets('old photo close cannot close the screen above it', (
    tester,
  ) async {
    await openViewer(tester, TaskFixture(), [() async => source]);
    await waitForPhoto(tester);
    final close = tester
        .widget<IconButton>(photoButton('Закрыть фотографию'))
        .onPressed!;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Экран поверх фотографии')),
      ),
    );
    await tester.pumpAndSettle();
    close();
    await tester.pumpAndSettle();
    expect(find.text('Экран поверх фотографии'), findsOneWidget);
    expect(find.byType(TaskPhotoViewer, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a covered gallery ignores an old next-photo action', (
    tester,
  ) async {
    var nextLoads = 0;
    await openViewer(tester, TaskFixture(), [
      () async => source,
      () async {
        nextLoads++;
        return source;
      },
    ]);
    await waitForPhoto(tester);
    final next = tester
        .widget<IconButton>(photoButton('Следующее фото'))
        .onPressed!;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Экран поверх фотографии')),
      ),
    );
    await tester.pumpAndSettle();
    next();
    await tester.pumpAndSettle();
    expect(nextLoads, 0);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Фото 1 из 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('photo controls are inert after the viewer is disposed', (
    tester,
  ) async {
    await openViewer(tester, TaskFixture(), [
      () async => source,
      () async => source,
    ]);
    await waitForPhoto(tester);
    final callbacks = [
      for (final tooltip in [
        'Увеличить',
        'Уменьшить',
        'Показать целиком',
        'Следующее фото',
        'Закрыть фотографию',
      ])
        tester.widget<IconButton>(photoButton(tooltip)).onPressed!,
    ];
    await tester.pumpWidget(const SizedBox.shrink());
    for (final callback in callbacks) {
      expect(callback, returnsNormally);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('photo download failure fits short landscape with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openViewer(tester, TaskFixture(), [
      () async => throw ApiFailure(503, 'Проверочная ошибка загрузки'),
    ], textScale: 2);
    await tester.pumpAndSettle();
    expect(find.text('Не удалось открыть фотографию'), findsOneWidget);
    await tester.ensureVisible(find.text('Повторить'));
    expect(find.text('Повторить').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final loading in [false, true]) {
    testWidgets(
      'replacement repository masks ${loading ? 'loading' : 'loaded'} photo',
      (tester) async {
        final first = TaskFixture(), next = TaskFixture();
        final selected = ValueNotifier(first);
        final download = Completer<File>();
        addTearDown(() async {
          if (!download.isCompleted) download.complete(source);
          await tester.pumpWidget(const SizedBox.shrink());
          selected.dispose();
          first.client.close();
          first.dispose();
          next.client.close();
          next.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ValueListenableBuilder<TaskFixture>(
                      valueListenable: selected,
                      builder: (_, owner, _) => TaskPhotoViewer(
                        key: const ValueKey('one-viewer'),
                        repository: owner,
                        photos: [
                          loading ? () => download.future : () async => source,
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Открыть'));
        await tester.pump(const Duration(milliseconds: 400));
        if (!loading) await waitForPhoto(tester);
        selected.value = next;
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(TaskPhotoViewer, skipOffstage: false), findsNothing);
        expect(
          find.byType(InteractiveViewer, skipOffstage: false),
          findsNothing,
        );
        if (!download.isCompleted) download.complete(source);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
