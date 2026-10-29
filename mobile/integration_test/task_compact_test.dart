import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:path_provider/path_provider.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/task_compact_test.dart' show compactFixture;
import '../test/task_photo_navigation_test.dart' show SubmittedPhotoFixture;
import '../test/task_photo_viewer_test.dart' show waitForPhoto, photoTransform;
import '../test/task_time_labels_test.dart' show TaskTimeFixture;
import 'task_photo_viewer_test.dart' show samplePage;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android child and parent use compact cards with optional details',
    (tester) async {
      final child = compactFixture('child');
      final parent = compactFixture('parent');
      final active = TaskTimeFixture(role: 'child');
      final directory = await Directory(
        '${(await getApplicationSupportDirectory()).path}/synthetic-compact-task-test',
      ).create(recursive: true);
      final page = await samplePage(directory, 1);
      final reviewer = SubmittedPhotoFixture({'first': page, 'second': page});
      await binding.convertFlutterSurfaceToImage();
      Future<void> show(FamilyRepository repo, {bool review = false}) =>
          mountFields(
            tester,
            Scaffold(
              appBar: AppBar(
                title: Text(
                  repo.role == 'child' ? 'Задания ребёнка' : 'Задания семьи',
                ),
              ),
              body: TaskScreen(
                key: ObjectKey(repo),
                repository: repo,
                reviewTaskId: review ? 'task' : null,
                perform: (_) async =>
                    fail('Viewing must not change family tasks'),
              ),
            ),
            child: repo.role == 'child',
            scale: 1.6,
            screenSize: null,
          );
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        await binding.takeScreenshot('task-compact-$name');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        expect(tester.takeException(), isNull);
      }

      try {
        await show(child);
        await revealField(tester, find.byKey(const ValueKey('task-morning')));
        expect(find.textContaining('Штраф за невыполнение'), findsNothing);
        expect(find.textContaining('Отмечено:'), findsNothing);
        await capture('child');
        final childHeight = tester
            .getSize(find.byKey(const ValueKey('task-morning')))
            .height;
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('task-morning')),
            matching: find.text('Подробнее'),
          ),
        );
        await revealField(tester, find.text('Получено: 14.10.2026 23:53'));
        expect(find.textContaining('2026-10-14T'), findsNothing);
        await capture('details');
        await show(parent);
        await revealField(tester, find.byKey(const ValueKey('task-morning')));
        await capture('parent');
        final parentHeight = tester
            .getSize(find.byKey(const ValueKey('task-morning')))
            .height;
        await show(active);
        final submit = find.descendant(
          of: find.byKey(const ValueKey('task-morning')),
          matching: find.text('Готово — отправить на проверку'),
        );
        await revealField(tester, submit);
        expect(find.textContaining('Проверяет:'), findsNothing);
        await capture('active');
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(find.text('Отправить результат'), findsOneWidget);
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
        await show(reviewer, review: true);
        await revealField(tester, find.text('Посмотреть фото 2'));
        expect(find.text('Подтвердить выполнение'), findsOneWidget);
        expect(find.textContaining('Проверяет:'), findsNothing);
        await capture('review');
        await tester.tap(find.text('Посмотреть фото 2'));
        await waitForPhoto(tester);
        await tester.tap(find.byTooltip('Увеличить'));
        await tester.pumpAndSettle();
        expect(
          photoTransform(tester).value.getMaxScaleOnAxis(),
          greaterThan(1),
        );
        await tester.tap(find.byTooltip('Закрыть фотографию'));
        await tester.pumpAndSettle();
        binding.reportData = {
          ...?binding.reportData,
          'synthetic_only': true,
          'text_scale': 1.6,
          'child_card_height': childHeight,
          'parent_card_height': parentHeight,
          'details_optional': true,
          'timestamps_readable': true,
          'primary_actions_visible': true,
          'review_photos_zoomable': true,
          'physical_devices_tested': false,
        };
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await directory.delete(recursive: true);
        for (final repo in [child, parent, active, reviewer]) {
          repo.client.close();
          repo.dispose();
        }
      }
    },
  );
}
