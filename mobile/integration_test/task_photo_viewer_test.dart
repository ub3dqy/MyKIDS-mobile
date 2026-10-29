import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/task_photo_viewer.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/submission_photos_test.dart' show PhotoFixture, tapPhotoPicker;
import '../test/task_photo_navigation_test.dart' show SubmittedPhotoFixture;
import '../test/task_photo_viewer_test.dart' show photoTransform, waitForPhoto;

Future<File> samplePage(Directory directory, int number) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1700, 2400),
    Paint()..color = Colors.white,
  );
  void text(String value, double y, {double size = 44}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: Colors.black, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 1500);
    painter.paint(canvas, Offset(100, y));
    painter.dispose();
  }

  text('Математика. Страница $number', 100, size: 66);
  text('Пример для проверки просмотра фотографий', 220);
  text('1. Продолжи ряд: 3, 6, 12, 24, __, __', 370);
  text('2. У Пети 18 монет. Он потратил 7 монет.', 560);
  text('Сколько монет осталось? Ответ: 11.', 635);
  text('3. В двух коробках 25 карандашей.', 830);
  text('В первой на 5 больше. Ответ: 15 и 10.', 905);
  text('4. 8 × 7 = 56. Проверка: 56 : 7 = 8.', 1100);
  text('5. Сумма трёх соседних чисел равна 36.', 1290);
  text('Ответ: 11, 12, 13.', 1365);
  text('6. Нарисуй три разных прямоугольника.', 1560);
  canvas.drawRect(
    const Rect.fromLTWH(150, 1700, 400, 250),
    Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6,
  );
  text('Все фотографии и данные в этом тесте вымышлены.', 2200, size: 36);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1700, 2400);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${directory.path}/page-$number.png');
  await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
  image.dispose();
  picture.dispose();
  return file;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android previews both selected pages and zooms reviewed work', (
    tester,
  ) async {
    tzdata.initializeTimeZones();
    final directory = await Directory(
      '${(await getApplicationSupportDirectory()).path}/synthetic-viewer-test',
    ).create(recursive: true);
    final first = await samplePage(directory, 1);
    final second = await samplePage(directory, 2);
    final child = PhotoFixture();
    await child.prepare();
    final parent = SubmittedPhotoFixture({'first': first, 'second': second});
    await binding.convertFlutterSurfaceToImage();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      // Allow Android's surface to present the frame before a native capture.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await binding.takeScreenshot('photo-viewer-$name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(tester.takeException(), isNull);
    }

    try {
      await mountFields(
        tester,
        Scaffold(
          body: TaskScreen(
            repository: child,
            selectPhotos: (_) async => [first.path, second.path],
            perform: (action) async => fail('Preview must not send the task'),
          ),
        ),
        scale: 1.3,
        screenSize: null,
      );
      await tester.tap(find.text('Две страницы математики'));
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Готово — отправить на проверку'));
      await tester.tap(find.text('Готово — отправить на проверку'));
      await tester.pumpAndSettle();
      await tapPhotoPicker(tester);
      await revealField(tester, find.text('Фото 1'));
      await tester.tap(find.text('Фото 1'));
      await waitForPhoto(tester);
      await capture('selected-fit');
      final viewport = find.byType(InteractiveViewer);
      final center = tester.getCenter(viewport);
      final fingerOne = await tester.createGesture(pointer: 1);
      final fingerTwo = await tester.createGesture(pointer: 2);
      await fingerOne.down(center - const Offset(40, 0));
      await fingerTwo.down(center + const Offset(40, 0));
      await tester.pump();
      await fingerOne.moveTo(center - const Offset(90, 0));
      await fingerTwo.moveTo(center + const Offset(90, 0));
      await tester.pump();
      await fingerOne.moveTo(center - const Offset(130, 0));
      await fingerTwo.moveTo(center + const Offset(130, 0));
      await tester.pump();
      await fingerOne.up();
      await fingerTwo.up();
      await tester.pumpAndSettle();
      expect(
        photoTransform(tester).value.getMaxScaleOnAxis(),
        greaterThan(1.4),
      );
      await capture('selected-pinch');
      await tester.tap(find.byTooltip('Следующее фото'));
      await waitForPhoto(tester);
      expect(find.text('Фото 2 из 2'), findsOneWidget);
      expect(photoTransform(tester).value, Matrix4.identity());
      await capture('selected-second');
      await tester.tap(find.byTooltip('Закрыть фотографию'));
      await tester.pumpAndSettle();
      expect(find.text('Всего фотографий: 2'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      await mountFields(
        tester,
        Scaffold(
          body: TaskScreen(
            key: ObjectKey(parent),
            repository: parent,
            reviewTaskId: 'task',
            perform: (action) async =>
                fail('Viewing must not approve the task'),
          ),
        ),
        scale: 1.3,
        screenSize: null,
      );
      await revealField(tester, find.text('Посмотреть фото 2'));
      await tester.tap(find.text('Посмотреть фото 2'));
      await waitForPhoto(tester);
      expect(parent.loaded, ['second']);
      final point = tester.getCenter(find.byType(InteractiveViewer));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(photoTransform(tester).value.getMaxScaleOnAxis(), closeTo(3, .01));
      await tester.drag(find.byType(InteractiveViewer), const Offset(-40, 100));
      await capture('review-zoom');
      await tester.tap(find.byTooltip('Показать целиком'));
      await tester.pumpAndSettle();
      await capture('review-fit');
      parent.token = null;
      parent.generation++;
      parent.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(TaskPhotoViewer), findsNothing);
      expect(child.mutations, isEmpty);
      expect(parent.mutations, isEmpty);
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'selected_pages': 2,
        'pinch_zoom': true,
        'double_tap_zoom': true,
        'pan': true,
        'parent_review': true,
        'session_close': true,
        'physical_devices_tested': false,
      };
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await child.closePhotos();
      await directory.delete(recursive: true);
      for (final repo in [child, parent]) {
        repo.client.close();
        repo.dispose();
      }
    }
  });
}
