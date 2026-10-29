import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/school_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'field_layout_test.dart' show mountFields, revealField;
import 'support/calendar_results_fixture.dart';

import 'support/owned_temp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final edit in [false, true]) {
    testWidgets(
      'grade form double save sends one command with its opened revision: $edit',
      (tester) async {
        final repo = ResultsFixture();
        addTearDown(() {
          repo.client.close();
          repo.dispose();
        });
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final revision = 'a' * 64;
        if (edit) {
          repo.snapshot!['grades'] = [
            {
              'id': 'saved',
              'subject_id': 'old-subject',
              'date': '2026-10-12',
              'grade': 4,
              'note': '',
              'revision': revision,
            },
          ];
        }
        await mountFields(
          tester,
          SchoolScreen(
            repository: repo,
            gradesOnly: true,
            initialDay: DateTime(2026, 10, 12),
            perform: (action) async {
              await action();
            },
          ),
          scale: 1.2,
        );
        final opener = edit
            ? find.byKey(const ValueKey('result-history-saved'))
            : find.byKey(
                const ValueKey(
                  'result-grade-schedule:school:2026-10-12:$mathIdentity',
                ),
              );
        await revealField(tester, opener);
        final point = tester.getCenter(opener);
        await tester.tapAt(point);
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(find.byType(FamilyForm, skipOffstage: false), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('5').last);
        await tester.pumpAndSettle();
        await revealField(tester, find.text('Сохранить'));
        final save = tester.getCenter(find.text('Сохранить'));
        await tester.tapAt(save);
        await tester.tapAt(save);
        await tester.pumpAndSettle();
        expect(repo.changes, hasLength(1));
        expect(repo.changes.single['method'], edit ? 'PUT' : 'POST');
        final body = repo.changes.single['body'] as Map;
        expect(body['grade'], 5);
        if (edit) {
          expect(body['expected_revision'], revision);
        } else {
          expect(body.containsKey('expected_revision'), false);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (edit, status) in [(false, 409), (true, 409), (true, 404)]) {
    test(
      'grade conflict refreshes all counters and never retries rejected write: $edit, $status',
      () async {
        final folder = await Directory.systemTemp.createTemp(
          'mykids-grade-race-',
        );
        await databaseFactory.setDatabasesPath(folder.path);
        FlutterSecureStorage.setMockInitialValues({
          'session': 'synthetic-grade-session',
          'endpoint': 'https://family.example',
        });
        var posts = 0, snapshots = 0;
        final repo = FamilyRepository(
          client: MockClient((request) async {
            final writing = request.method != 'GET';
            if (writing) {
              posts++;
            } else {
              snapshots++;
            }
            return http.Response(
              jsonEncode(
                writing
                    ? {'detail': 'Оценка уже изменена другим родителем'}
                    : {
                        'user': {'id': 'mama', 'role': 'parent'},
                        'balance': {
                          'total': 25,
                          'reserved': 0,
                          'available': 25,
                        },
                        'grades': [
                          {'id': 'grade', 'grade': 5, 'revision': 'b' * 64},
                        ],
                        'penalties': [],
                      },
              ),
              writing ? status : 200,
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
            'balance': {'total': 0, 'reserved': 0, 'available': 0},
            'grades': edit
                ? [
                    {'id': 'grade', 'grade': 3},
                  ]
                : [],
            'penalties': [],
          };
          await expectLater(
            repo.mutate(edit ? '/v1/grades/grade' : '/v1/grades', {
              'grade': 4,
            }, method: edit ? 'PUT' : 'POST'),
            throwsA(
              isA<ApiFailure>().having((e) => e.status, 'status', status),
            ),
          );
          expect(snapshots, 1);
          expect(repo.signedIn, true);
          expect(repo.rows('grades').single['grade'], 5);
          expect(repo.snapshot!['balance']['total'], 25);
          expect(repo.rows('penalties'), isEmpty);
          final data = jsonDecode(
            (await repo.db!.query('cache')).single['data'] as String,
          );
          expect(data['grades'].single['grade'], 5);
          expect((await repo.pending()).single['state'], 'failed');
          await repo.sync();
          expect(posts, 1);
        } finally {
          await repo.db?.close();
          repo.client.close();
          repo.dispose();
          await deleteOwnedTestTemp(folder);
        }
      },
    );
  }
}
