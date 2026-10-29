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
    for (final op in ['edit', 'delete', 'request', 'goal']) {
      test(
        'catalogue conflict refreshes all counters and never retries rejected write: $op $status',
        () async {
          final child = op == 'request' || op == 'goal';
          final folder = await Directory.systemTemp.createTemp(
            'mykids-reward-catalog-',
          );
          await databaseFactory.setDatabasesPath(folder.path);
          FlutterSecureStorage.setMockInitialValues({
            'session': 'synthetic-catalogue-session',
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
                      ? {'detail': 'Награда уже изменена другим родителем'}
                      : {
                          'user': {
                            'id': child ? 'kid' : 'mama',
                            'role': child ? 'child' : 'parent',
                          },
                          'balance': {
                            'total': 25,
                            'reserved': 0,
                            'available': 25,
                          },
                          'rewards': [
                            {
                              'id': 'reward',
                              'title': 'Изменено другим родителем',
                              'price': 60,
                              'available': 1,
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
              'user': {
                'id': child ? 'kid' : 'mama',
                'role': child ? 'child' : 'parent',
              },
              'balance': {'total': 0, 'reserved': 0, 'available': 0},
              'rewards': [
                {
                  'id': 'reward',
                  'title': 'Старое название',
                  'revision': 'a' * 64,
                },
              ],
              'penalties': [],
            };
            await expectLater(
              repo.mutate(
                op == 'request'
                    ? '/v1/redemptions'
                    : op == 'goal'
                    ? '/v1/goal'
                    : '/v1/rewards/reward',
                op == 'request'
                    ? {'reward_id': 'reward', 'expected_price': 25}
                    : op == 'goal'
                    ? {'reward_id': 'reward'}
                    : {
                        'expected_revision': 'a' * 64,
                        if (op == 'edit') ...{
                          'title': 'Награда',
                          'description': '',
                          'price': 40,
                          'available': true,
                        },
                      },
                method: op == 'edit' || op == 'goal'
                    ? 'PUT'
                    : op == 'delete'
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
              repo.rows('rewards').single['title'],
              'Изменено другим родителем',
            );
            expect(repo.snapshot!['balance']['total'], 25);
            expect(repo.rows('penalties'), isEmpty);
            final data = jsonDecode(
              (await repo.db!.query('cache')).single['data'] as String,
            );
            expect(
              data['rewards'].single['title'],
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
