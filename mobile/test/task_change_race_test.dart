import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'task_edit_test.dart' show TaskEditFixture;
import 'task_rules_test.dart' show showTasks, reveal;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final operation in [
    'edit',
    'cancel',
    'reschedule',
    'plan',
    'stop_repeat',
  ]) {
    testWidgets(
      'task $operation captures opened version and blocks double taps',
      (tester) async {
        final repo = TaskEditFixture(withTask: true);
        addTearDown(() {
          repo.client.close();
          repo.dispose();
        });
        if (operation == 'stop_repeat') {
          (repo.snapshot!['tasks'] as List).first['recurrence_id'] = 'daily';
          repo.snapshot!['task_recurrences'] = [
            {'id': 'daily', 'active': 1, 'weekdays': '[1,3,5]', 'until': null},
          ];
        }
        await showTasks(tester, repo);
        if (operation == 'stop_repeat') {
          await tester.tap(find.text('Ждут внимания'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Убрать игрушки'));
        await tester.pumpAndSettle();
        final label = {
          'edit': 'Редактировать задание',
          'cancel': 'Отменить',
          'reschedule': 'Перенести',
          'plan': 'Время в календаре',
          'stop_repeat': 'Остановить повторение',
        }[operation]!;
        await reveal(tester, find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        if (operation == 'stop_repeat') {
          final confirm = find.widgetWithText(
            FilledButton,
            'Остановить повтор',
          );
          await tester.tap(confirm);
          await tester.pumpAndSettle();
        } else {
          // A foreground refresh replaces the task while this form stays open.
          repo.snapshot!['tasks'] = [
            {...repo.rows('tasks').single, 'version': 8},
          ];
          repo.notifyListeners();
          await tester.pumpAndSettle();
          await reveal(tester, find.text('Сохранить'));
          final point = tester.getCenter(find.text('Сохранить'));
          await tester.tapAt(point);
          await tester.tapAt(point);
          await tester.pumpAndSettle();
        }
        expect(repo.mutations, hasLength(1));
        expect(repo.mutations.single['task_version'], 7);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
