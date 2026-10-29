import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/repository.dart';

import 'settings_account_safety_test.dart';

Future<ValueChanged<bool>?> permissionButton(
  WidgetTester tester,
  AccountSettingsFixture repo, {
  ValueNotifier<AccountSettingsFixture>? selection,
  Future<void> Function(Future<Map<String, dynamic>> Function())? perform,
}) async {
  await mountAccountSettings(
    tester,
    repo,
    selection: selection,
    perform: perform,
  );
  await tester.scrollUntilVisible(
    find.text('Бабушка'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Бабушка'));
  await tester.pumpAndSettle();
  final label = find.text('Смотреть свои задания');
  await tester.ensureVisible(label);
  return tester
      .widget<SwitchListTile>(
        find.ancestor(of: label, matching: find.byType(SwitchListTile)),
      )
      .onChanged;
}

void main() {
  for (final change in [
    'account',
    'server',
    'generation',
    'role restored before a frame',
    'revision',
    'member removed',
    'member role',
    'offline',
  ]) {
    testWidgets('old relative-permission action is rejected after $change', (
      tester,
    ) async {
      final repo = AccountSettingsFixture();
      final callback = (await permissionButton(tester, repo))!;
      final member = (repo.snapshot!['members'] as List).first as Map;
      switch (change) {
        case 'account':
          repo.token = 'another-synthetic-parent';
          repo.snapshot!['user'] = {'id': 'other-parent', 'role': 'parent'};
        case 'server':
          repo.endpoint = 'https://another-synthetic.invalid';
        case 'generation':
          repo.generation++;
        case 'role restored before a frame':
          repo.snapshot!['user']['role'] = 'child';
          repo.notifyListeners();
          repo.snapshot!['user']['role'] = 'parent';
        case 'revision':
          member['permissions_revision'] = 'b' * 64;
          member['create_tasks'] = 0;
        case 'member removed':
          (repo.snapshot!['members'] as List).clear();
        case 'member role':
          member['role'] = 'child';
        case 'offline':
          repo.online = false;
      }
      repo.notifyListeners();
      callback(false);
      await tester.pumpAndSettle();
      expect(repo.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'relative-permission callback cannot change a replacement owner',
    (tester) async {
      final repo = AccountSettingsFixture(), next = AccountSettingsFixture();
      final selected = ValueNotifier(repo);
      addTearDown(() {
        selected.dispose();
        next.client.close();
        next.dispose();
      });
      final callback = (await permissionButton(
        tester,
        repo,
        selection: selected,
      ))!;
      selected.value = next;
      await tester.pumpAndSettle();
      callback(false);
      await tester.pumpAndSettle();
      expect(repo.changes, isEmpty);
      expect(next.changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a covered settings screen cannot change relative permissions', (
    tester,
  ) async {
    final repo = AccountSettingsFixture();
    final callback = (await permissionButton(tester, repo))!;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Другой семейный экран')),
      ),
    );
    await tester.pumpAndSettle();
    callback(false);
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(find.text('Другой семейный экран'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fresh owner controls still change only the chosen permission', (
    tester,
  ) async {
    final repo = AccountSettingsFixture(), next = AccountSettingsFixture();
    final selected = ValueNotifier(repo);
    addTearDown(() {
      selected.dispose();
      next.client.close();
      next.dispose();
    });
    final old = (await permissionButton(tester, repo, selection: selected))!;
    selected.value = next;
    await tester.pumpAndSettle();
    old(false);
    await tester.pumpAndSettle();
    final fresh = tester
        .widget<SwitchListTile>(
          find.ancestor(
            of: find.text('Смотреть свои задания'),
            matching: find.byType(SwitchListTile),
          ),
        )
        .onChanged!;
    fresh(false);
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(next.changes.single['body'], {
      'view_tasks': false,
      'expected_revision': 'a' * 64,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'permission editing recovers after reconnection with fresh controls',
    (tester) async {
      final repo = AccountSettingsFixture()..online = false;
      expect(await permissionButton(tester, repo), isNull);
      expect(find.textContaining('Подключитесь к интернету'), findsWidgets);
      repo.online = true;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      final tile = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Смотреть свои задания'),
          matching: find.byType(SwitchListTile),
        ),
      );
      tile.onChanged!(false);
      await tester.pumpAndSettle();
      expect(repo.changes.single['body'], {
        'view_tasks': false,
        'expected_revision': 'a' * 64,
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a permission deferred by perform rechecks its original owner', (
    tester,
  ) async {
    final repo = AccountSettingsFixture();
    final gate = Completer<void>();
    final errors = <Object>[];
    final callback = (await permissionButton(
      tester,
      repo,
      perform: (action) async {
        await gate.future;
        try {
          await action();
        } catch (error) {
          errors.add(error);
        }
      },
    ))!;
    callback(false);
    repo.generation++;
    repo.notifyListeners();
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(
      errors.single,
      isA<ApiFailure>().having((e) => e.status, 'status', 409),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late permission completion cannot report success to another owner',
    (tester) async {
      final repo = AccountSettingsFixture()
        ..reply = Completer<Map<String, dynamic>>();
      final errors = <Object>[], results = <Map<String, dynamic>>[];
      final callback = (await permissionButton(
        tester,
        repo,
        perform: (action) async {
          try {
            results.add(await action());
          } catch (error) {
            errors.add(error);
          }
        },
      ))!;
      callback(false);
      await tester.pump();
      expect(repo.changes, hasLength(1));
      repo.generation++;
      repo.notifyListeners();
      repo.reply!.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(
        errors.single,
        isA<ApiFailure>().having((e) => e.status, 'status', 409),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
