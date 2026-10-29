import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/task_time_labels_test.dart' show TaskTimeFixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'identical recurring tasks expose morning and evening calendar times before expansion',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      final repo = TaskTimeFixture();
      await mountFields(
        tester,
        Scaffold(
          appBar: AppBar(title: const Text('MyKIDS · Папа')),
          body: TaskScreen(
            repository: repo,
            perform: (action) async {
              await action();
            },
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 2,
            destinations: [
              for (final entry in [
                'Сегодня',
                'Календарь',
                'Задания',
                'Монеты',
                'Семья',
              ].indexed)
                NavigationDestination(
                  icon: FamilyIcon(entry.$1),
                  label: entry.$2,
                ),
            ],
          ),
        ),
        scale: 1.2,
        screenSize: null,
      );
      await tester.runAsync(
        () => precacheFamilyArtwork(tester.element(find.byType(Scaffold))),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name, String label) async {
        await revealField(tester, find.text(label));
        expect(find.text(label), findsOneWidget);
        expect(find.text('Редактировать задание'), findsNothing);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await binding.takeScreenshot('task-time-$name');
        expect(tester.takeException(), isNull);
      }

      await capture('morning', repo.morningLabel);
      await capture('evening', repo.eveningLabel);
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'same_title_and_deadline': true,
        'calendar_times_visible_collapsed': true,
        'morning': repo.morningLabel,
        'evening': repo.eveningLabel,
        'text_scale': 1.2,
      };
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    },
  );
}
