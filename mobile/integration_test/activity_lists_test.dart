import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/activity_lists.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/settings_screen.dart';
import 'package:mykids_family/visuals.dart';

import '../test/activity_lists_test.dart' show ActivityFixture, select;
import '../test/field_layout_test.dart' show mountFields, revealField;

class AndroidActivityFixture extends ActivityFixture {
  @override
  Future<List<Map<String, Object?>>> pending() async => [];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'today, history and penalty layout on Android with enlarged text',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      final repo = AndroidActivityFixture();
      Future<void> perform(
        Future<Map<String, dynamic>> Function() action,
      ) async {
        await action();
      }

      Future<void> show(Widget page, int selected) async {
        await mountFields(
          tester,
          Scaffold(
            appBar: AppBar(title: const Text('MyKIDS · Папа')),
            body: page,
            bottomNavigationBar: NavigationBar(
              selectedIndex: selected,
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
          scale: 1.4,
          screenSize: null,
        );
        await tester.runAsync(
          () => precacheFamilyArtwork(tester.element(find.byType(Scaffold))),
        );
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await binding.takeScreenshot('activity-$name');
        expect(tester.takeException(), isNull);
      }

      await show(TodayScreen(repository: repo, openPage: (_) {}), 0);
      await revealField(tester, find.byType(TodayTaskList));
      expect(find.text('Найдено: 32'), findsOneWidget);
      await capture('today');
      await select(tester, 'Состояние задания', 'Выполнено');
      expect(find.text('Найдено: 1'), findsOneWidget);
      await capture('today-filtered');

      await show(
        SettingsScreen(
          repository: repo,
          background: BackgroundServices(repo),
          perform: perform,
          onUpdates: () async {},
        ),
        0,
      );
      await revealField(tester, find.byType(ActionHistory));
      await select(tester, 'Вид действия', 'Предметы и оценки');
      expect(find.text('Найдено: 30'), findsOneWidget);
      await revealField(tester, find.byType(ActionHistory));
      await capture('history');

      await show(MoneyScreen(repository: repo, perform: perform), 3);
      await revealField(
        tester,
        find.text('Срок задания: Умывание с чисткой зубов'),
      );
      await capture('penalty');
      await revealField(tester, find.text('Отменить'));
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(repo.changes.single, '/v1/penalties/fine/waive');
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'enlarged_text': 1.4,
        'today_filters': true,
        'history_filters': true,
        'penalty_actions_below_text': true,
        'penalty_action_reachable': true,
      };
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    },
  );
}
