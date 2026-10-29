import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_rewards.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/submission_photos_test.dart' show PhotoFixture;
import '../test/task_result_rewards_test.dart' show ResultRewardFixture;

class NativeRewardFixture extends ResultRewardFixture {
  NativeRewardFixture() : super(status: 'assigned');
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    final result = await super.mutate(
      path,
      body,
      method: method,
      offlineSubmission: offlineSubmission,
      files: files,
    );
    if (body['action'] == 'approve') {
      task.addAll({
        'status': 'completed',
        'completed_count': body['completed_count'],
        'awarded_reward': taskRewardForCount(
          taskRewardOptions(task)!,
          body['completed_count'] as int,
        ),
      });
      notifyListeners();
    }
    return result;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'graded rewards, native multiple photo selection and post-submission correction',
    (tester) async {
      tzdata.initializeTimeZones();
      await binding.convertFlutterSurfaceToImage();
      Future<void> show(FamilyRepository repo) => mountFields(
        tester,
        Scaffold(
          body: TaskScreen(
            key: ObjectKey(repo),
            repository: repo,
            perform: (action) async {
              await action();
            },
          ),
        ),
        scale: 1.3,
        screenSize: null,
      );
      Future<void> reveal(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 100));
        await revealField(tester, finder);
      }

      Future<void> capture(String name) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await binding.takeScreenshot('task-result-$name');
        expect(tester.takeException(), isNull);
      }

      Future<void> waitForSuccess() async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
          if (find.text('Здорово!').evaluate().isNotEmpty) return;
        }
        expect(find.text('Здорово!'), findsOneWidget);
      }

      final parent = NativeRewardFixture();
      await show(parent);
      await tester.tap(find.text('Ждут внимания'));
      await tester.pumpAndSettle();
      await reveal(find.text('Математика: шесть задач'));
      await tester.tap(find.text('Математика: шесть задач'));
      await tester.pumpAndSettle();
      await reveal(find.text('Редактировать задание'));
      await tester.tap(find.text('Редактировать задание'));
      await tester.pumpAndSettle();
      await reveal(find.byKey(const ValueKey('reward-total')));
      await capture('rules-upper');
      await reveal(find.byKey(const ValueKey('reward-coins-1')));
      await capture('rules-lower');
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      parent.task['status'] = 'submitted';
      parent.notifyListeners();
      await tester.pumpAndSettle();
      await reveal(find.text('Подтвердить выполнение'));
      await tester.tap(find.text('Подтвердить выполнение'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-completed-count')),
        '5',
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('review-25');
      expect(find.text('Начислить: 25 монет'), findsOneWidget);
      await tester.tap(find.text('Подтвердить результат'));
      await tester.pumpAndSettle();
      expect(parent.mutations.single['completed_count'], 5);
      await tester.tap(find.text('Ждут внимания'));
      await tester.pumpAndSettle();
      await reveal(find.text('+25 монет'));
      await capture('verified-25');

      final child = PhotoFixture();
      await child.prepare();
      await show(child);
      await reveal(find.text('Две страницы математики'));
      await tester.tap(find.text('Две страницы математики'));
      await tester.pumpAndSettle();
      await reveal(find.text('Готово — отправить на проверку'));
      await tester.tap(find.text('Готово — отправить на проверку'));
      await tester.pumpAndSettle();
      await reveal(find.text('Добавить фото'));
      await tester.tap(find.text('Добавить фото'));
      // The host selects two synthetic pages in Android's real photo picker.
      for (var attempt = 0; attempt < 240; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pump();
        if (find.text('Всего фотографий: 2').evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.text('Всего фотографий: 2'), findsOneWidget);
      await reveal(find.text('Всего фотографий: 2'));
      await capture('two-pages');
      await tester.tap(find.text('Отправить на проверку'));
      await tester.pumpAndSettle();
      expect(child.mutations.single['files'], hasLength(2));
      await waitForSuccess();
      await tester.tap(find.text('Здорово!'));
      await tester.pumpAndSettle();
      final correction = PhotoFixture(submitted: true, minimum: 1);
      await correction.prepare();
      await show(correction);
      await reveal(find.text('Две страницы математики'));
      await tester.tap(find.text('Две страницы математики'));
      await tester.pumpAndSettle();
      await reveal(find.text('Добавить фото к результату'));
      await capture('supplement-one');
      await tester.tap(find.text('Добавить фото к результату'));
      await tester.pumpAndSettle();
      await reveal(find.text('Добавить фото'));
      await tester.tap(find.text('Добавить фото'));
      for (var attempt = 0; attempt < 240; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pump();
        if (find.text('Всего фотографий: 2').evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.text('Всего фотографий: 2'), findsOneWidget);
      await capture('supplement-two');
      await tester.tap(find.text('Дослать фото'));
      await tester.pumpAndSettle();
      expect(correction.mutations.single['submission_id'], 'result');
      expect(correction.mutations.single['files'], hasLength(1));
      expect(
        correction.snapshot!['submissions'][0]['attachment_ids'],
        jsonEncode(['page-one']),
      );
      await waitForSuccess();
      await tester.tap(find.text('Здорово!'));
      await tester.pumpAndSettle();
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'native_gallery_selection': true,
        'selected_together': 2,
        'supplemented_photos': 1,
        'verified_count': 5,
        'reward_preview': 25,
        'no_physical_devices': true,
        'text_scale': 1.3,
      };
      await tester.pumpWidget(const SizedBox.shrink());
      await child.closePhotos();
      await correction.closePhotos();
      parent.client.close();
      parent.dispose();
      child.client.close();
      child.dispose();
      correction.client.close();
      correction.dispose();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
