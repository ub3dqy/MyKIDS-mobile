import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'activity_lists_test.dart' show ActivityFixture;
import 'field_layout_test.dart' show mountFields, revealField;

import 'support/owned_temp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  testWidgets(
    'repeated payout taps request one authentication and one command',
    (tester) async {
      final repo = ActivityFixture()..token = 'synthetic-payout';
      repo.snapshot!['penalties'] = [];
      repo.snapshot!['redemptions'] = [
        {
          'id': 'request',
          'title': 'Конструктор',
          'amount': 25,
          'status': 'claimed',
          'claimed_by': 'dad',
        },
      ];
      var authentications = 0, saved = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/local_auth');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'authenticate') {
          throw StateError('Unexpected authentication call');
        }
        authentications++;
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        repo.client.close();
        repo.dispose();
      });
      await mountFields(
        tester,
        Scaffold(
          body: MoneyScreen(
            repository: repo,
            perform: (action) async {
              saved++;
              await action();
            },
          ),
        ),
        scale: 1.2,
      );
      await revealField(tester, find.text('Конструктор · 25'));
      await tester.tap(find.text('Конструктор · 25'));
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Уже выдал — подтвердить'));
      final button = tester.getCenter(find.text('Уже выдал — подтвердить'));
      await tester.tapAt(button);
      await tester.tapAt(button);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      final confirm = tester.getCenter(
        find.widgetWithText(FilledButton, 'Подтвердить'),
      );
      await tester.tapAt(confirm);
      await tester.tapAt(confirm);
      await tester.pumpAndSettle();
      expect(authentications, 1);
      expect(saved, 1);
      expect(repo.changes, ['/v1/redemptions/request/actions']);
      expect(tester.takeException(), isNull);
    },
  );
  for (final status in [403, 409]) {
    test(
      'competing redemption $status refreshes the request and wallet before returning',
      () async {
        final folder = await Directory.systemTemp.createTemp(
          'mykids-redemption-race-',
        );
        await databaseFactory.setDatabasesPath(folder.path);
        FlutterSecureStorage.setMockInitialValues({
          'session': 'synthetic-redemption-session',
          'endpoint': 'https://family.example',
        });
        var posts = 0, snapshots = 0;
        final repo = FamilyRepository(
          client: MockClient((request) async {
            final body = request.method == 'POST'
                ? {'detail': 'Заявку обрабатывает другой родитель'}
                : {
                    'user': {'id': 'mama', 'role': 'parent'},
                    'balance': {'total': 75, 'reserved': 0, 'available': 75},
                    'redemptions': [
                      {
                        'id': 'request',
                        'status': 'confirmed',
                        'claimed_by': 'papa',
                        'amount': 25,
                      },
                    ],
                  };
            if (request.method == 'POST') {
              posts++;
            } else {
              snapshots++;
            }
            return http.Response(
              jsonEncode(body),
              request.method == 'POST' ? status : 200,
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
            'balance': {'total': 100, 'reserved': 25, 'available': 75},
            'redemptions': [
              {
                'id': 'request',
                'status': status == 403 ? 'claimed' : 'pending',
                'claimed_by': 'mama',
                'amount': 25,
              },
            ],
          };
          await expectLater(
            repo.mutate('/v1/redemptions/request/actions', {
              'action': status == 403 ? 'confirm' : 'claim',
            }),
            throwsA(
              isA<ApiFailure>().having((e) => e.status, 'status', status),
            ),
          );
          expect(snapshots, 1);
          expect(repo.signedIn, true);
          expect(repo.rows('redemptions').single['status'], 'confirmed');
          expect(repo.snapshot!['balance']['total'], 75);
          expect(
            repo
                .rows('redemptions')
                .where((r) => ['pending', 'claimed'].contains(r['status'])),
            isEmpty,
          );
          final data = jsonDecode(
            (await repo.db!.query('cache')).single['data'] as String,
          );
          expect(data['balance']['total'], 75);
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
