import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_photo_viewer.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'field_layout_test.dart' show mountFields, revealField;
import 'task_photo_viewer_test.dart' show waitForPhoto;
import 'task_rules_test.dart' show TaskFixture;

class SubmittedPhotoFixture extends TaskFixture {
  final Map<String, File> photos;
  final loaded = <String>[];
  SubmittedPhotoFixture(this.photos, {String role = 'parent'})
    : super(userRole: role, withTask: true) {
    (snapshot!['tasks'] as List).first['status'] = 'submitted';
    snapshot!['submissions'] = [
      {
        'id': 'result',
        'task_id': 'task',
        'accepted': 1,
        'note': 'Две страницы',
        'attachment_ids': '["first","second"]',
        'marked_at': '2026-10-14T10:00:00Z',
        'received_at': '2026-10-14T10:00:01Z',
      },
    ];
  }

  @override
  Future<File> attachment(String id) async {
    loaded.add(id);
    return photos[id]!;
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  final source = File('assets/generated/calendar-task.png').absolute;

  for (final role in ['parent', 'child']) {
    testWidgets(
      '$role opens the second submitted page and returns to the task',
      (tester) async {
        final repo = SubmittedPhotoFixture({
          'first': source,
          'second': source,
        }, role: role);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mountFields(
          tester,
          Scaffold(
            body: TaskScreen(
              repository: repo,
              reviewTaskId: role == 'parent' ? 'task' : null,
              perform: (action) async =>
                  fail('Viewing must not submit anything'),
            ),
          ),
          scale: 1.6,
        );
        await tester.pumpAndSettle();
        if (role == 'child') {
          await tester.tap(find.text('Убрать игрушки'));
          await tester.pumpAndSettle();
        }
        await revealField(tester, find.text('Посмотреть фото 2'));
        await tester.tap(find.text('Посмотреть фото 2'));
        await waitForPhoto(tester);
        expect(find.text('Фото 2 из 2'), findsOneWidget);
        expect(repo.loaded, ['second']);
        await tester.tap(find.byTooltip('Предыдущее фото'));
        await waitForPhoto(tester);
        expect(repo.loaded, ['second', 'first']);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(TaskPhotoViewer), findsNothing);
        expect(find.text('Результат: Две страницы'), findsOneWidget);
        expect(repo.mutations, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.client.close();
        repo.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('replacing the family repository removes the previous photo', (
    tester,
  ) async {
    final first = SubmittedPhotoFixture({'first': source, 'second': source});
    final second = SubmittedPhotoFixture({'first': source, 'second': source});
    final selection = ValueNotifier<FamilyRepository>(first);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<FamilyRepository>(
            valueListenable: selection,
            builder: (context, repo, _) => TaskScreen(
              repository: repo,
              reviewTaskId: 'task',
              perform: (action) async => fail('Viewing must not mutate'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Посмотреть фото 1'));
    await tester.tap(find.text('Посмотреть фото 1'));
    await waitForPhoto(tester);
    expect(find.byType(TaskPhotoViewer), findsOneWidget);
    selection.value = second;
    await tester.pumpAndSettle();
    expect(find.byType(TaskPhotoViewer), findsNothing);
    expect(second.loaded, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    selection.dispose();
    for (final repo in [first, second]) {
      repo.client.close();
      repo.dispose();
    }
    expect(tester.takeException(), isNull);
  });
}
