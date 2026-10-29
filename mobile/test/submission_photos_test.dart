import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'field_layout_test.dart' show mountFields, revealField;
import 'task_rules_test.dart' show TaskFixture;
import 'task_photo_viewer_test.dart' show waitForPhoto, photoTransform;

class PhotoFixture extends TaskFixture {
  late final Directory photoFolder;
  var sequence = 0;
  PhotoFixture({bool submitted = false, int minimum = 2})
    : super(userRole: 'child', withTask: true) {
    task.addAll({
      'title': 'Две страницы математики',
      'due_at': DateTime.now().toUtc().toIso8601String(),
      'require_photo': 1,
      'required_photos': minimum,
      'status': submitted ? 'submitted' : 'assigned',
    });
    snapshot!['submissions'] = [
      if (submitted)
        {
          'id': 'result',
          'task_id': 'task',
          'accepted': 1,
          'note': 'Первая страница',
          'attachment_ids': jsonEncode(['page-one']),
          'marked_at': '2026-10-14T10:00:00Z',
          'received_at': '2026-10-14T10:00:01Z',
        },
    ];
  }
  Map<String, dynamic> get task =>
      (snapshot!['tasks'] as List).first as Map<String, dynamic>;
  Future<void> prepare() async {
    photoFolder = await Directory.systemTemp.createTemp('mykids-photo-test-');
  }

  Future<void> closePhotos() async {
    await photoFolder.delete(recursive: true);
  }

  @override
  Future<String> keepFile(String source) async =>
      (await File(source)
              .copy('${photoFolder.path}/selected-${sequence++}.png'))
          .path;
  @override
  Future<List<Map<String, Object?>>> pending() async => [];
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    mutations.add({
      'path': path,
      ...body,
      'files': files.toList(),
      'offlineSubmission': offlineSubmission,
    });
    task['status'] = 'submitted';
    return {'accepted': true, 'id': 'result'};
  }
}

Future<void> mountPhotoTask(
  WidgetTester tester,
  PhotoFixture repo,
  Future<List<String>> Function(int) select,
) => mountFields(
  tester,
  Scaffold(
    body: TaskScreen(
      repository: repo,
      selectPhotos: select,
      perform: (action) async {
        await action();
      },
    ),
  ),
  scale: 1.6,
);

Future<void> tapPhotoPicker(WidgetTester tester) async {
  await revealField(tester, find.text('Добавить фото'));
  await tester.tap(find.text('Добавить фото'));
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.text('Добавляем фотографии…').evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
  expect(find.text('Добавляем фотографии…'), findsNothing);
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  final source = File('assets/generated/calendar-task.png').absolute.path;

  testWidgets(
    'one gallery selection attaches both pages and one page cannot be submitted',
    (tester) async {
      final repo = PhotoFixture();
      await tester.runAsync(repo.prepare);
      await mountPhotoTask(tester, repo, (limit) async {
        expect(limit, 5);
        return [source];
      });
      await revealField(tester, find.text('Две страницы математики'));
      await tester.tap(find.text('Две страницы математики'));
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Готово — отправить на проверку'));
      await tester.tap(find.text('Готово — отправить на проверку'));
      await tester.pumpAndSettle();
      await tapPhotoPicker(tester);
      expect(find.text('Всего фотографий: 1'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Отправить на проверку'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Отмена'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await mountPhotoTask(tester, repo, (limit) async {
        expect(limit, 5);
        return [source, source];
      });
      await revealField(tester, find.text('Две страницы математики'));
      await tester.tap(find.text('Две страницы математики'));
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Готово — отправить на проверку'));
      await tester.tap(find.text('Готово — отправить на проверку'));
      await tester.pumpAndSettle();
      await tapPhotoPicker(tester);
      expect(find.text('Всего фотографий: 2'), findsOneWidget);
      await revealField(tester, find.text('Фото 2'));
      await tester.tap(find.text('Фото 2'));
      await waitForPhoto(tester);
      expect(find.text('Фото 2 из 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Увеличить'));
      await tester.pump();
      expect(photoTransform(tester).value.getMaxScaleOnAxis(), greaterThan(1));
      await tester.tap(find.byTooltip('Закрыть фотографию'));
      await tester.pumpAndSettle();
      expect(find.text('Всего фотографий: 2'), findsOneWidget);
      await tester.tap(find.text('Отправить на проверку'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['files'], hasLength(2));
      expect(repo.mutations.single['offlineSubmission'], isTrue);
      expect(
        find.text(
          'Результат отправлен семье. Монеты появятся после проверки взрослым.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Здорово!'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(File(source).existsSync(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(repo.closePhotos);
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets(
    'child can add a second photo to the submitted result but not to a completed result',
    (tester) async {
      final repo = PhotoFixture(submitted: true, minimum: 1);
      await tester.runAsync(repo.prepare);
      await mountPhotoTask(tester, repo, (limit) async {
        expect(limit, 4);
        return [source];
      });
      await revealField(tester, find.text('Две страницы математики'));
      await tester.tap(find.text('Две страницы математики'));
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Добавить фото к результату'));
      await tester.tap(find.text('Добавить фото к результату'));
      await tester.pumpAndSettle();
      await tapPhotoPicker(tester);
      expect(find.text('Всего фотографий: 2'), findsOneWidget);
      await tester.tap(find.text('Дослать фото'));
      await tester.pumpAndSettle();
      expect(repo.mutations.single['path'], '/v1/tasks/task/submission-photos');
      expect(repo.mutations.single['submission_id'], 'result');
      expect(repo.mutations.single['task_version'], 7);
      expect(repo.mutations.single['files'], hasLength(1));
      expect(repo.mutations.single.containsKey('note'), isFalse);
      await tester.tap(find.text('Здорово!'));
      await tester.pumpAndSettle();
      repo.task['status'] = 'completed';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Добавить фото к результату'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(repo.closePhotos);
      repo.client.close();
      repo.dispose();
    },
  );
}
