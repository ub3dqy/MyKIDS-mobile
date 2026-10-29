import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/task_rules_test.dart' show TaskFixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'task types, large fields and explicit adult confirmation on Android',
    (tester) async {
      tzdata.initializeTimeZones();
      await binding.convertFlutterSurfaceToImage();
      Future<void> show(TaskFixture repo) => mountFields(
        tester,
        Scaffold(
          body: TaskScreen(
            repository: repo,
            perform: (action) async {
              await action();
            },
          ),
        ),
        scale: 1.6,
        screenSize: null,
      );
      Future<void> reveal(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 100));
        await revealField(tester, finder);
      }

      Future<void> capture(String name) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 350)),
        );
        await binding.takeScreenshot('task-rules-$name');
        expect(tester.takeException(), isNull);
      }

      final parent = TaskFixture(withTask: true);
      await show(parent);
      await tester.tap(find.text('Добавить задание'));
      await tester.pumpAndSettle();
      await reveal(find.byKey(const ValueKey('field-is_required')));
      await capture('required-type');
      await reveal(find.byKey(const ValueKey('field-penalty')));
      expect(find.text('Штраф за невыполнение в монетах'), findsOneWidget);
      await capture('penalty-field');
      await reveal(find.byKey(const ValueKey('field-is_required')));
      await tester.tap(find.byKey(const ValueKey('field-is_required')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Необязательное').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-penalty')), findsNothing);
      await capture('optional-type');
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await reveal(find.text('Убрать игрушки'));
      await tester.tap(find.text('Убрать игрушки'));
      await tester.pumpAndSettle();
      await reveal(find.text('Не выполнено — назначить штраф'));
      await tester.tap(find.text('Не выполнено — назначить штраф'));
      await tester.pumpAndSettle();
      expect(parent.mutations, isEmpty);
      await capture('adult-confirmation');
      await tester.tap(find.text('Подтвердить штраф'));
      await tester.pumpAndSettle();
      expect(parent.mutations.single['action'], 'not_completed');
      expect(parent.mutations.single['task_version'], 7);
      final child = TaskFixture(userRole: 'child', withTask: true);
      await show(child);
      await reveal(find.text('Убрать игрушки'));
      expect(find.textContaining('Штраф за невыполнение: 15'), findsOneWidget);
      expect(find.text('Не выполнено — назначить штраф'), findsNothing);
      await capture('child-terms');
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'large_text_scale': 1.6,
        'optional_penalty_hidden': true,
        'adult_confirmed_once': true,
        'child_cannot_fine': true,
      };
      await tester.pumpWidget(const SizedBox.shrink());
      parent.client.close();
      parent.dispose();
      child.client.close();
      child.dispose();
    },
  );
}
