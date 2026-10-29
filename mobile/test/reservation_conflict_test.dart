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
  for (final available in [0, 20, -5]) {
    test(
      'cash reservation conflict refreshes wallet and counters: $available',
      () async {
        final folder = await Directory.systemTemp.createTemp(
          'mykids-cash-conflict-',
        );
        await databaseFactory.setDatabasesPath(folder.path);
        FlutterSecureStorage.setMockInitialValues({
          'endpoint': 'https://family.example',
          'session': 'synthetic-cash-session',
        });
        var posts = 0, snapshots = 0;
        final fresh = {
          'user': {'id': 'kid', 'role': 'child'},
          'balance': {
            'total': 100 + available,
            'reserved': 100,
            'available': available,
          },
          'redemptions': [
            {'id': 'gift-request', 'status': 'pending', 'amount': 40},
            {'id': 'cash-request', 'status': 'claimed', 'amount': 60},
          ],
        };
        final repo = FamilyRepository(
          client: MockClient((request) async {
            if (request.method == 'POST') {
              posts++;
              expect(request.url.path, '/v1/redemptions');
              expect(jsonDecode(request.body), {'amount': 60});
              return http.Response(
                jsonEncode({'detail': 'Недостаточно доступных монет'}),
                409,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            snapshots++;
            expect(request.url.path, '/v1/snapshot');
            return http.Response(
              jsonEncode(fresh),
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
            'user': {'id': 'kid', 'role': 'child'},
            'balance': {'total': 100, 'reserved': 0, 'available': 100},
            'redemptions': [],
          };
          await expectLater(
            repo.mutate('/v1/redemptions', {'amount': 60}),
            throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
          );
          expect(snapshots, 1);
          expect(repo.snapshot!['balance'], fresh['balance']);
          expect(repo.rows('redemptions'), hasLength(2));
          final cache = jsonDecode(
            (await repo.db!.query('cache')).single['data'] as String,
          );
          expect(cache['balance'], fresh['balance']);
          expect(cache['redemptions'], fresh['redemptions']);
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
