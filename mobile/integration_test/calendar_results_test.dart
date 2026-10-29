import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/school_screen.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/support/calendar_results_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('dated lessons and reviewed family tasks on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    Future<void> show(ResultsFixture repo, {double scale = 1.2}) => mountFields(
      tester,
      SchoolScreen(
        key: ValueKey(repo.role),
        repository: repo,
        gradesOnly: true,
        initialDay: DateTime(2026, 10, 12),
        perform: (action) async {
          await action();
        },
      ),
      scale: scale,
      screenSize: null,
    );
    Future<void> capture(String name) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('results-$name');
    }

    final parent = ResultsFixture();
    await show(parent);
    await capture('parent-events');
    final math = find.byKey(
      const ValueKey('result-grade-schedule:school:2026-10-12:$mathIdentity'),
    );
    await revealField(tester, math);
    await tester.tap(math);
    await tester.pumpAndSettle();
    expect(find.text('Оценка: Математика'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    await capture('grade-form');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(parent.changes.single['body']['date'], '2026-10-12');
    expect(parent.changes.single['body']['activity_id'], mathIdentity);
    expect(find.byKey(const ValueKey('results-date')), findsOneWidget);
    await tester.tap(find.byTooltip('Следующий день'));
    await tester.pumpAndSettle();
    expect(find.text('Вт, 13.10.2026'), findsOneWidget);
    await capture('next-date');
    final child = ResultsFixture(role: 'child');
    child.snapshot!['schedules'] = [];
    await show(child, scale: 2);
    final submit = find.byKey(const ValueKey('result-submit-help'));
    await revealField(tester, submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(child.changes.single['path'], '/v1/tasks/help/submissions');
    expect(find.byKey(const ValueKey('result-complete-help')), findsNothing);
    await capture('child-review');
    final relative = ResultsFixture(role: 'relative');
    relative.snapshot!['schedules'] = [];
    await show(relative, scale: 2);
    final complete = find.byKey(const ValueKey('result-complete-help'));
    await revealField(tester, complete);
    await tester.tap(complete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Выполнено'));
    await tester.pumpAndSettle();
    expect(relative.changes.single['body'], {
      'action': 'complete',
      'date': '2026-10-12',
      'task_version': 3,
    });
    expect(find.text('Награда начислена'), findsOneWidget);
    await capture('relative-completed');
    binding.reportData = {
      ...?binding.reportData,
      'synthetic_only': true,
      'roles': ['parent', 'child', 'relative'],
      'grade_date': '2026-10-12',
      'grade_activity_id': mathIdentity,
      'child_submitted': true,
      'relative_confirmed': true,
      'large_text_scale': 2,
      'physical_device_tested': false,
    };
  });
}
