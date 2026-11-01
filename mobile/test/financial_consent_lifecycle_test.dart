import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/task_rules.dart';

import 'financial_approval_test.dart' show proposal, release;
import 'task_rules_test.dart' show TaskFixture;

class ConsentProbe {
  final navigator = GlobalKey<NavigatorState>();
  final decisions = <bool>[];
}

Future<ConsentProbe> showConsent(WidgetTester tester, TaskFixture repo) async {
  final probe = ConsentProbe();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: probe.navigator,
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              probe.decisions.add(
                await confirmTaskFinances(
                  context,
                  repo,
                  repo.rows('tasks').single,
                ),
              );
            },
            child: const Text('Открыть условия'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть условия'));
  await tester.pumpAndSettle();
  return probe;
}

VoidCallback consentButton(WidgetTester tester, bool accept) => accept
    ? tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-task-finances')),
          )
          .onPressed!
    : tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Вернуться'))
          .onPressed!;

void main() {
  for (final accept in [true, false]) {
    testWidgets('hidden consent cannot close another screen: $accept', (
      tester,
    ) async {
      final repo = proposal();
      addTearDown(() => release(repo));
      final probe = await showConsent(tester, repo);
      final callback = consentButton(tester, accept);
      probe.navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Другой экран')),
        ),
      );
      await tester.pumpAndSettle();

      callback();
      await tester.pumpAndSettle();
      expect(find.text('Другой экран'), findsOneWidget);
      expect(probe.decisions, isEmpty);
      expect(tester.takeException(), isNull);

      probe.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      consentButton(tester, accept)();
      await tester.pumpAndSettle();
      expect(probe.decisions, [accept]);
    });

    testWidgets('disposed consent ignores an old callback: $accept', (
      tester,
    ) async {
      final repo = proposal();
      addTearDown(() => release(repo));
      final probe = await showConsent(tester, repo);
      final callback = consentButton(tester, accept);
      probe.navigator.currentState!.pop(false);
      await tester.pumpAndSettle();

      expect(callback, returnsNormally);
      await tester.pumpAndSettle();
      expect(probe.decisions, [false]);
      expect(find.text('Открыть условия'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final change in [
    'revision',
    'reward',
    'penalty',
    'scope',
    'offline',
    'session',
    'server',
    'member',
  ]) {
    testWidgets('old approval rechecks $change before the next frame', (
      tester,
    ) async {
      final repo = proposal();
      addTearDown(() => release(repo));
      final probe = await showConsent(tester, repo);
      final callback = consentButton(tester, true);
      final task = (repo.snapshot!['tasks'] as List).single as Map;
      switch (change) {
        case 'revision':
          task['version'] = 8;
        case 'reward':
          task['reward'] = 500;
        case 'penalty':
          task['penalty'] = 500;
        case 'scope':
          task['financial_approval_scope'] = 'repeat';
        case 'offline':
          repo.online = false;
        case 'session':
          repo.generation++;
        case 'server':
          repo.endpoint = 'https://another-synthetic.invalid';
        case 'member':
          (repo.snapshot!['user'] as Map)['id'] = 'another-synthetic-parent';
      }
      repo.notifyListeners();
      callback();
      await tester.pumpAndSettle();

      expect(probe.decisions, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm-task-finances')), findsNothing);
      expect(repo.mutations, isEmpty);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(probe.decisions, [false]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('nested reward edits cannot change the displayed agreement', (
    tester,
  ) async {
    final repo = proposal();
    addTearDown(() => release(repo));
    final task = (repo.snapshot!['tasks'] as List).single as Map;
    task['reward_options'] = {
      'total': 6,
      'tiers': [
        {'minimum': 6, 'coins': 50},
      ],
    };
    final probe = await showConsent(tester, repo);
    final callback = consentButton(tester, true);
    ((task['reward_options'] as Map)['tiers'] as List).single['coins'] = 500;
    repo.notifyListeners();
    callback();
    await tester.pumpAndSettle();

    expect(probe.decisions, isEmpty);
    expect(find.textContaining('500 монет'), findsNothing);
    expect(find.byKey(const ValueKey('confirm-task-finances')), findsNothing);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(probe.decisions, [false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a replaced family identity cannot revive an old consent', (
    tester,
  ) async {
    final repo = proposal();
    addTearDown(() => release(repo));
    final probe = await showConsent(tester, repo);
    final callback = consentButton(tester, true);
    final user = repo.snapshot!['user'] as Map;
    final id = user['id'];
    user['id'] = 'another-synthetic-parent';
    repo.notifyListeners();
    user['id'] = id;
    repo.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confirm-task-finances')), findsNothing);
    callback();
    await tester.pumpAndSettle();
    expect(probe.decisions, isEmpty);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(probe.decisions, [false]);
    expect(tester.takeException(), isNull);
  });
}
