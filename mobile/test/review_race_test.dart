import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'field_layout_test.dart' show mountFields, revealField;
import 'task_result_rewards_test.dart' show ResultRewardFixture;

import 'support/owned_temp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('rapid review taps open one result dialog', (tester) async {
    final repo = ResultRewardFixture();
    addTearDown(() {
      repo.client.close();
      repo.dispose();
    });
    await mountFields(
      tester,
      Scaffold(
        body: TaskScreen(
          repository: repo,
          reviewTaskId: 'task',
          perform: (action) async {
            await action();
          },
        ),
      ),
      scale: 1.2,
    );
    await revealField(tester, find.text('Подтвердить выполнение'));
    final button = tester.getCenter(find.text('Подтвердить выполнение'));
    await tester.tapAt(button);
    await tester.tapAt(button);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('task-completed-count')),
      '5',
    );
    await tester.pumpAndSettle();
    final confirm = tester.getCenter(find.text('Подтвердить результат'));
    await tester.tapAt(confirm);
    await tester.tapAt(confirm);
    await tester.pumpAndSettle();
    expect(repo.mutations, hasLength(1));
    expect(repo.mutations.single['completed_count'], 5);
    expect(tester.takeException(), isNull);
  });

  test(
    'a rejected competing review immediately refreshes task and coins',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final folder = await Directory.systemTemp.createTemp(
        'mykids-review-race-',
      );
      await databaseFactory.setDatabasesPath(folder.path);
      FlutterSecureStorage.setMockInitialValues({
        'session': 'synthetic-review-race',
        'endpoint': 'https://family.example',
      });
      var snapshotRequests = 0;
      var reviewRequests = 0;
      final repo = FamilyRepository(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            reviewRequests++;
            return http.Response(
              jsonEncode({'detail': 'Результат уже проверен другим родителем'}),
              409,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          snapshotRequests++;
          return http.Response(
            jsonEncode({
              'user': {'id': 'mama', 'role': 'parent'},
              'balance': {'total': 25, 'available': 25, 'reserved': 0},
              'tasks': [
                {
                  'id': 'task',
                  'status': 'completed',
                  'version': 2,
                  'awarded_reward': 25,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      try {
        await repo.initialize();
        await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
        repo.online = true;
        repo.snapshot = {
          'user': {'id': 'mama', 'role': 'parent'},
          'balance': {'total': 0, 'available': 0, 'reserved': 0},
          'tasks': [
            {'id': 'task', 'status': 'submitted', 'version': 1},
          ],
        };
        await expectLater(
          repo.mutate('/v1/tasks/task/actions', {
            'action': 'approve',
            'task_version': 1,
            'completed_count': 6,
          }),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
        );
        expect(snapshotRequests, 1);
        expect(repo.rows('tasks').single['status'], 'completed');
        expect(repo.snapshot!['balance']['total'], 25);
        expect(
          repo.rows('tasks').where((t) => t['status'] == 'submitted'),
          isEmpty,
        );
        final reopened = await repo.db!.query('cache');
        expect(
          jsonDecode(reopened.single['data'] as String)['balance']['total'],
          25,
        );
        expect((await repo.pending()).single['state'], 'failed');
        await repo.sync();
        expect(reviewRequests, 1);
        expect(repo.snapshot!['balance']['total'], 25);
      } finally {
        await repo.db?.close();
        repo.client.close();
        repo.dispose();
        await deleteOwnedTestTemp(folder);
      }
    },
  );
}
