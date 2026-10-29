import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'activity_lists_test.dart' show ActivityFixture;
import 'field_layout_test.dart' show mountFields, revealField;

import 'support/owned_temp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  testWidgets('repeated penalty taps confirm and authenticate once', (
    tester,
  ) async {
    final repo = ActivityFixture()..token = 'synthetic-penalty';
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
    await revealField(tester, find.text('Применить'));
    final button = tester.getCenter(find.text('Применить'));
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
    expect(repo.changes, ['/v1/penalties/fine/approve']);
    expect(tester.takeException(), isNull);
  });

  test('stale penalty conflict refreshes submitted task and counters without retrying the debit', () async {
    final folder = await Directory.systemTemp.createTemp(
      'mykids-penalty-race-',
    );
    await databaseFactory.setDatabasesPath(folder.path);
    FlutterSecureStorage.setMockInitialValues({
      'session': 'synthetic-penalty-session',
      'endpoint': 'https://family.example',
    });
    var posts = 0, snapshots = 0;
    final repo = FamilyRepository(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          return http.Response(
            jsonEncode({
              'detail': 'Задание отправлено на проверку. Штраф не применяется',
            }),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        snapshots++;
        return http.Response(
          jsonEncode({
            'user': {'id': 'papa', 'role': 'parent'},
            'balance': {'total': 30, 'reserved': 0, 'available': 30},
            'tasks': [
              {'id': 'task', 'status': 'submitted'},
            ],
            'penalties': [
              {'id': 'fine', 'status': 'pending', 'amount': 500},
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
        'user': {'id': 'papa', 'role': 'parent'},
        'balance': {'total': 30, 'reserved': 0, 'available': 30},
        'tasks': [
          {'id': 'task', 'status': 'assigned'},
        ],
        'penalties': [
          {'id': 'fine', 'status': 'pending', 'amount': 500},
        ],
      };
      await expectLater(
        repo.mutate('/v1/penalties/fine/approve', {}),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
      );
      expect(snapshots, 1);
      expect(repo.signedIn, true);
      expect(
        repo.rows('tasks').where((r) => r['status'] == 'submitted'),
        hasLength(1),
      );
      expect(repo.rows('penalties').single['status'], 'pending');
      expect(repo.snapshot!['balance']['total'], 30);
      final data = jsonDecode(
        (await repo.db!.query('cache')).single['data'] as String,
      );
      expect(data['tasks'].single['status'], 'submitted');
      expect((await repo.pending()).single['state'], 'failed');
      await repo.sync();
      expect(posts, 1);
    } finally {
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
      await deleteOwnedTestTemp(folder);
    }
  });
}
