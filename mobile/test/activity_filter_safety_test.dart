import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/activity_lists.dart';
import 'package:mykids_family/repository.dart';

import 'activity_lists_test.dart' show ActivityFixture, select;

const longLabel = 'Сегодня и просроченные задания';

void expectWholeLabel(WidgetTester tester, Finder label) {
  final paragraph = tester.renderObject<RenderParagraph>(label);
  final natural = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(natural.height - .1),
    reason: 'The actual label must have room for every wrapped line',
  );
  natural.dispose();
}

Finder filter(String label) => find.byWidgetPredicate(
  (widget) => widget is ActivityFilter && widget.label == label,
);

Future<void> mountFilter(
  WidgetTester tester,
  ValueNotifier<Map<String, String>> choices,
  List<String> changes, {
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    choices.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ValueListenableBuilder<Map<String, String>>(
              valueListenable: choices,
              builder: (_, options, _) => ActivityFilter(
                label: 'Участник',
                value: 'all',
                choices: options,
                onChanged: changes.add,
              ),
            ),
            const Text('Следующий раздел'),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> mountLists(
  WidgetTester tester,
  ActivityFixture repo, {
  required bool history,
  ValueNotifier<FamilyRepository>? selection,
}) async {
  repo.token = 'synthetic-activity-owner';
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
    selection?.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([repo, ?selection]),
          builder: (_, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (history)
                ActionHistory(repository: selection?.value ?? repo)
              else
                TodayTaskList(
                  repository: selection?.value ?? repo,
                  onOpen: () {},
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final popup in [false, true]) {
    testWidgets(
      'large filter label is whole ${popup ? 'in menu' : 'when closed'}',
      (tester) async {
        final choices = ValueNotifier({'all': longLabel, 'other': 'Все даты'});
        await mountFilter(tester, choices, [], scale: 2);
        if (popup) {
          await tester.tap(find.byType(DropdownButton<String>));
          await tester.pumpAndSettle();
        }
        expectWholeLabel(tester, find.text(longLabel).last);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an open filter discards removed choices after a real rebuild', (
    tester,
  ) async {
    final choices = ValueNotifier({
      'all': 'Все участники',
      'former': 'Участник из прежнего списка',
    });
    final changes = <String>[];
    await mountFilter(tester, choices, changes);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(
      find.text('Участник из прежнего списка').last.hitTestable(),
      findsOneWidget,
    );
    choices.value = {'all': 'Все участники', 'new': 'Новый участник'};
    await tester.pumpAndSettle();
    expect(find.text('Участник из прежнего списка'), findsNothing);
    expect(changes, isEmpty);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый участник').last);
    await tester.pumpAndSettle();
    expect(changes, ['new']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged refreshed choices keep the open filter usable', (
    tester,
  ) async {
    final choices = ValueNotifier({'all': 'Все участники', 'mom': 'Мама'});
    final changes = <String>[];
    await mountFilter(tester, choices, changes);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    choices.value = {...choices.value};
    await tester.pumpAndSettle();
    expect(find.text('Мама').last.hitTestable(), findsOneWidget);
    await tester.tap(find.text('Мама').last);
    await tester.pumpAndSettle();
    expect(changes, ['mom']);
    expect(tester.takeException(), isNull);
  });

  for (final history in [false, true]) {
    testWidgets(
      '${history ? 'history' : 'tasks'} can reset a narrowed empty list',
      (tester) async {
        final repo = ActivityFixture();
        await mountLists(tester, repo, history: history);
        await select(
          tester,
          history ? 'Вид действия' : 'Состояние задания',
          history ? 'Монеты и награды' : 'Не выполнено',
        );
        expect(find.text('Найдено: 0'), findsOneWidget);
        expect(find.text('Сбросить фильтры'), findsOneWidget);
        await tester.ensureVisible(find.text('Сбросить фильтры'));
        await tester.tap(find.text('Сбросить фильтры'));
        await tester.pumpAndSettle();
        expect(
          find.text(history ? 'Найдено: 130' : 'Найдено: 32'),
          findsOneWidget,
        );
        expect(find.text('Сбросить фильтры'), findsNothing);
        expect(repo.changes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    for (final change in ['repository', 'session', 'server', 'generation']) {
      testWidgets(
        '${history ? 'history' : 'tasks'} starts with default filters for $change',
        (tester) async {
          final repo = ActivityFixture(), next = ActivityFixture();
          next.token = 'synthetic-activity-owner';
          final selection = ValueNotifier<FamilyRepository>(repo);
          addTearDown(() {
            next.client.close();
            next.dispose();
          });
          await mountLists(
            tester,
            repo,
            history: history,
            selection: selection,
          );
          final periodLabel = history ? 'Период истории' : 'Период заданий';
          await select(
            tester,
            periodLabel,
            history ? 'Вся доступная история' : 'Все даты',
          );
          switch (change) {
            case 'repository':
              selection.value = next;
            case 'session':
              repo.token = 'another-synthetic-activity-owner';
            case 'server':
              repo.endpoint = 'https://another-family.invalid';
            case 'generation':
              repo.generation++;
          }
          repo.notifyListeners();
          await tester.pumpAndSettle();
          expect(
            tester.widget<ActivityFilter>(filter(periodLabel)).value,
            history ? 'week' : 'today',
          );
          expect(repo.changes, isEmpty);
          expect(next.changes, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('removed history actor stays cleared when their entries return', (
    tester,
  ) async {
    final repo = ActivityFixture();
    await mountLists(tester, repo, history: true);
    await select(tester, 'Участник', 'Мама');
    expect(find.text('Найдено: 30'), findsOneWidget);
    final original = List<Map<String, dynamic>>.from(repo.rows('audit'));
    repo.snapshot!['audit'] = original
        .where((row) => row['actor_id'] != 'mom')
        .toList();
    repo.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.widget<ActivityFilter>(filter('Участник')).value, 'all');
    repo.snapshot!['audit'] = original;
    repo.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.widget<ActivityFilter>(filter('Участник')).value, 'all');
    expect(find.text('Найдено: 130'), findsOneWidget);
    expect(repo.changes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
