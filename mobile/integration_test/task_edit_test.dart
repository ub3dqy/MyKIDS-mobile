import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/task_screen.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/task_edit_test.dart' show TaskEditFixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('either parent, zero reward and edit existing task on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final repo = TaskEditFixture(withTask: true);
    await mountFields(
      tester,
      Scaffold(
        body: AnimatedBuilder(
          animation: repo,
          builder: (context, _) => TaskScreen(
            repository: repo,
            perform: (action) async {
              await action();
            },
          ),
        ),
      ),
      scale: 1.5,
      screenSize: null,
    );
    Future<void> reveal(Finder finder) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 100));
      await revealField(tester, finder);
    }

    Future<void> capture(String name) async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await binding.takeScreenshot('task-edit-$name');
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.text('Добавить задание'));
    await tester.pumpAndSettle();
    await reveal(find.byKey(const ValueKey('field-reviewer_id')));
    await tester.tap(find.byKey(const ValueKey('field-reviewer_id')));
    await tester.pumpAndSettle();
    expect(find.text('Мама'), findsOneWidget);
    expect(find.text('Папа'), findsOneWidget);
    await capture('reviewer-choices');
    await tester.tap(find.text('Мама или папа').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await reveal(find.text('Убрать игрушки'));
    await tester.tap(find.text('Убрать игрушки'));
    await tester.pumpAndSettle();
    await reveal(find.text('Редактировать задание'));
    await tester.tap(find.text('Редактировать задание'));
    await tester.pumpAndSettle();
    expect(find.text('Изменить задание'), findsOneWidget);
    await capture('prefilled-title');
    await tester.enterText(
      find.byKey(const ValueKey('field-title')),
      'Убрать книги',
    );
    await reveal(find.byKey(const ValueKey('field-reward')));
    await tester.enterText(find.byKey(const ValueKey('field-reward')), '0');
    await capture('zero-reward');
    await reveal(find.text('Сохранить'));
    await capture('save-visible');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repo.mutations.single['method'], 'PUT');
    expect(repo.mutations.single['path'], '/v1/tasks/task');
    expect(repo.mutations.single['task_version'], 7);
    expect(repo.mutations.single['reward'], 0);
    await reveal(find.text('Убрать книги'));
    expect(find.textContaining('Награды за выполнение нет.'), findsOneWidget);
    await capture('edited-task');
    binding.reportData = {
      ...?binding.reportData,
      'synthetic_only': true,
      'large_text_scale': 1.5,
      'both_parents_choice': true,
      'zero_reward_saved': true,
      'same_task_edited': true,
      'displayed_version_submitted': true,
    };
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });
}
