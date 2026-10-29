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
  for (final status in [404, 409]) {
    for (final op in ['edit', 'replace', 'cancel', 'archive']) {
      test(
        'calendar conflict refreshes all counters and never retries rejected write: $op $status',
        () async {
          final folder = await Directory.systemTemp.createTemp(
            'mykids-calendar-race-',
          );
          await databaseFactory.setDatabasesPath(folder.path);
          FlutterSecureStorage.setMockInitialValues({
            'session': 'synthetic-calendar-session',
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
                      ? {'detail': 'Событие уже изменено другим родителем'}
                      : {
                          'user': {'id': 'mama', 'role': 'parent'},
                          'balance': {
                            'total': 25,
                            'reserved': 0,
                            'available': 25,
                          },
                          'schedules': [
                            {
                              'id': 'event',
                              'title': 'Изменено другим родителем',
                              'revision': 'b' * 64,
                            },
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
            await repo.db!.insert('identity', {
              'id': 1,
              'tag': repo.sessionTag,
            });
            repo.online = true;
            repo.snapshot = {
              'user': {'id': 'mama', 'role': 'parent'},
              'balance': {'total': 0, 'reserved': 0, 'available': 0},
              'schedules': [
                {
                  'id': 'event',
                  'title': 'Старое название',
                  'revision': 'a' * 64,
                },
              ],
              'penalties': [],
            };
            await expectLater(
              repo.mutate(
                '/v1/schedules/event${op == 'replace' || op == 'cancel' ? '/exceptions' : ''}',
                {'expected_revision': 'a' * 64},
                method: op == 'edit'
                    ? 'PUT'
                    : op == 'archive'
                    ? 'DELETE'
                    : 'POST',
              ),
              throwsA(
                isA<ApiFailure>().having((e) => e.status, 'status', status),
              ),
            );
            expect(snapshots, 1);
            expect(repo.signedIn, true);
            expect(
              repo.rows('schedules').single['title'],
              'Изменено другим родителем',
            );
            expect(repo.snapshot!['balance']['total'], 25);
            expect(repo.rows('penalties'), isEmpty);
            final data = jsonDecode(
              (await repo.db!.query('cache')).single['data'] as String,
            );
            expect(
              data['schedules'].single['title'],
              'Изменено другим родителем',
            );
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
}
