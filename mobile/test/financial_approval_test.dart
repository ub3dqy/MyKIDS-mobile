import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/task_rules.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'task_rules_test.dart' show TaskFixture, showTasks;

TaskFixture proposal({String scope = 'single'}) {
  final repo = TaskFixture(withTask: true);
  final task = (repo.snapshot!['tasks'] as List).single as Map<String, dynamic>;
  task['financial_approved'] = 0;
  task['financial_approval_scope'] = scope;
  return repo;
}

Future<void> openConsent(WidgetTester tester) async {
  await openProposalTask(tester);
  final button = find.text('Согласовать награду и штраф');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> openProposalTask(WidgetTester tester) async {
  final title = find.text('Убрать игрушки');
  await tester.ensureVisible(title);
  await tester.tap(title);
  await tester.pumpAndSettle();
}

void release(TaskFixture repo) {
  repo.client.close();
  repo.dispose();
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  for (final accept in [true, false]) {
    testWidgets(
      'repeated consent close keeps the underlying task route: $accept',
      (tester) async {
        final repo = proposal();
        addTearDown(() => release(repo));
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Проверочное задание'),
                        ),
                        body: FilledButton(
                          onPressed: () => confirmTaskFinances(
                            context,
                            repo,
                            repo.rows('tasks').single,
                          ),
                          child: const Text('Открыть согласование'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Перейти к заданию'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Перейти к заданию'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Открыть согласование'));
        await tester.pumpAndSettle();
        final VoidCallback callback = accept
            ? tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('confirm-task-finances')),
                  )
                  .onPressed!
            : tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Вернуться'),
                  )
                  .onPressed!;
        callback();
        callback();
        await tester.pumpAndSettle();
        expect(find.text('Проверочное задание'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scope in ['single', 'repeat']) {
    testWidgets(
      'parent reviews $scope consent and submits shown revision once',
      (tester) async {
        final repo = proposal(scope: scope);
        addTearDown(() => release(repo));
        await showTasks(tester, repo);
        await openConsent(tester);
        expect(repo.mutations, isEmpty);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('Награда после проверки: 30 монет.'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('Штраф за невыполнение: 15 монет'),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            scope == 'repeat' ? 'включая будущие' : 'только этого задания',
          ),
          findsOneWidget,
        );
        final button = find.byKey(const ValueKey('confirm-task-finances'));
        await tester.ensureVisible(button);
        final point = tester.getCenter(button);
        await tester.tapAt(point);
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(repo.mutations, hasLength(1));
        expect(repo.mutations.single['task_version'], 7);
        expect(repo.mutations.single['financial_scope'], scope);
        expect(repo.mutations.single['action'], 'approve_finances');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('canceling financial consent sends no action', (tester) async {
    final repo = proposal();
    addTearDown(() => release(repo));
    await showTasks(tester, repo);
    await openConsent(tester);
    await tester.tap(find.text('Вернуться'));
    await tester.pumpAndSettle();
    expect(repo.mutations, isEmpty);
  });

  testWidgets('rapid proposal taps open only one consent window', (
    tester,
  ) async {
    final repo = proposal();
    addTearDown(() => release(repo));
    await showTasks(tester, repo);
    await openProposalTask(tester);
    final button = find.text('Согласовать награду и штраф');
    await tester.ensureVisible(button);
    final point = tester.getCenter(button);
    await tester.tapAt(point);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('Вернуться'));
    await tester.pumpAndSettle();
    expect(repo.mutations, isEmpty);
  });

  testWidgets(
    'changed or already approved terms close the consent opportunity',
    (tester) async {
      final repo = proposal();
      addTearDown(() => release(repo));
      await showTasks(tester, repo);
      await openConsent(tester);
      ((repo.snapshot!['tasks'] as List).single as Map)['version'] = 8;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirm-task-finances')), findsNothing);
      expect(find.textContaining('Условия задания изменились'), findsOneWidget);
      expect(repo.mutations, isEmpty);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('session change hides the proposal and prevents confirmation', (
    tester,
  ) async {
    final repo = proposal();
    addTearDown(() => release(repo));
    await showTasks(tester, repo);
    await openConsent(tester);
    repo.token = 'another-synthetic-session';
    repo.generation++;
    repo.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      find.text('Семейный доступ изменился. Закройте это окно.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('confirm-task-finances')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('30 монет'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(repo.mutations, isEmpty);
  });

  testWidgets('large text keeps the full consent and its actions reachable', (
    tester,
  ) async {
    final repo = proposal(scope: 'repeat');
    addTearDown(() => release(repo));
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => confirmTaskFinances(
                  context,
                  repo,
                  repo.rows('tasks').single,
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('confirm-task-finances'));
    await tester.ensureVisible(button);
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Вернуться'));
    await tester.pumpAndSettle();
  });
}
