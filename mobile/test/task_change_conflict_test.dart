import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/owned_temp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final op in ['edit', 'cancel', 'reschedule', 'plan', 'stop_repeat']) {
    test(
      'task conflict refreshes all counters and never retries rejected write: $op',
      () async {
        final folder = await Directory.systemTemp.createTemp(
          'mykids-task-change-',
        );
        await databaseFactory.setDatabasesPath(folder.path);
        FlutterSecureStorage.setMockInitialValues({
          'session': 'synthetic-task-session',
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
                    ? {'detail': 'Задание уже изменено другим родителем'}
                    : {
                        'user': {'id': 'mama', 'role': 'parent'},
                        'balance': {
                          'total': 25,
                          'reserved': 0,
                          'available': 25,
                        },
                        'tasks': [
                          {'id': 'task', 'status': 'cancelled', 'version': 8},
                        ],
                        'penalties': [],
                      },
              ),
              writing ? 409 : 200,
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
            'tasks': [
              {'id': 'task', 'status': 'assigned', 'version': 7},
            ],
            'penalties': [],
          };
          await expectLater(
            repo.mutate(
              '/v1/tasks/task${op == 'edit'
                  ? ''
                  : op == 'plan'
                  ? '/plan'
                  : '/actions'}',
              {'action': op, 'task_version': 7},
              method: op == 'edit'
                  ? 'PUT'
                  : op == 'plan'
                  ? 'PATCH'
                  : 'POST',
            ),
            throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
          );
          expect(snapshots, 1);
          expect(repo.signedIn, true);
          expect(repo.rows('tasks').single['status'], 'cancelled');
          expect(repo.snapshot!['balance']['total'], 25);
          expect(repo.rows('penalties'), isEmpty);
          final data = jsonDecode(
            (await repo.db!.query('cache')).single['data'] as String,
          );
          expect(data['tasks'].single['status'], 'cancelled');
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
