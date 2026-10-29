import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmanager/workmanager.dart';

import 'background_retry_test.dart' show RetryWorkmanager;
import 'task_reward_form_safety_test.dart'
    show FormSafetyFixture, mountSafety, openSafetyForm;
import 'task_rules_test.dart' show reveal;
import 'support/owned_temp.dart';

class QueuedFormFixture extends FormSafetyFixture {
  final bool transport;
  QueuedFormFixture(this.transport);

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    await super.mutate(
      path,
      body,
      method: method,
      offlineSubmission: offlineSubmission,
      files: files,
    );
    if (transport) {
      online = false;
      notifyListeners();
      return {'queued': true};
    }
    throw QueuedCommandFailure(
      503,
      'Временная ошибка сервера',
      commandId: 'synthetic-durable-command',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WorkmanagerPlatform originalJobs;
  setUp(() {
    originalJobs = WorkmanagerPlatform.instance;
    WorkmanagerPlatform.instance = RetryWorkmanager();
  });
  tearDown(() => WorkmanagerPlatform.instance = originalJobs);
  for (final interruption in [
    'server-before-commit',
    'server-after-commit',
    'transport',
  ]) {
    test('a durable reward uses one command through $interruption', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final folder = await Directory.systemTemp.createTemp(
        'mykids-form-outbox106-',
      );
      await databaseFactory.setDatabasesPath(folder.path);
      FlutterSecureStorage.setMockInitialValues({
        'session': 'synthetic-form-outbox',
        'endpoint': 'https://synthetic-family.example',
      });
      final seed = FormSafetyFixture();
      final data =
          jsonDecode(jsonEncode(seed.snapshot)) as Map<String, dynamic>;
      seed.client.close();
      seed.dispose();
      data['rewards'] = <Map<String, dynamic>>[];
      final receivedKeys = <String>[];
      final applied = <String, Map<String, dynamic>>{};
      var first = true;
      final repo = FamilyRepository(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode(data),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/rewards');
          final key = request.headers['Idempotency-Key']!;
          receivedKeys.add(key);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          void applyOnce() {
            applied.putIfAbsent(key, () {
              final row = {
                ...body,
                'id': 'created-reward',
                'available': 1,
                'revision': 'b' * 64,
              };
              (data['rewards'] as List).add(row);
              return row;
            });
          }

          if (first) {
            first = false;
            if (interruption == 'server-after-commit') applyOnce();
            if (interruption == 'transport') {
              throw http.ClientException('Synthetic interrupted response');
            }
            return http.Response(
              jsonEncode({'detail': 'Временная ошибка сервера'}),
              503,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          applyOnce();
          return http.Response(
            jsonEncode({'id': 'created-reward'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      try {
        await repo.initialize();
        await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
        repo.snapshot = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
        repo.online = true;
        final body = {
          'title': 'Награда без дублей',
          'description': 'Описание',
          'price': 1,
          'available': true,
        };
        String? commandId;
        if (interruption == 'transport') {
          final response = await repo.mutate('/v1/rewards', body);
          expect(response['queued'], isTrue);
        } else {
          try {
            await repo.mutate('/v1/rewards', body);
            fail('An uncertain response must identify its durable command');
          } on QueuedCommandFailure catch (error) {
            expect(error.status, 503);
            commandId = error.commandId;
          }
        }
        final pending = await repo.pending();
        expect(pending, hasLength(1));
        expect(pending.single['state'], 'pending');
        expect(pending.single['id'], commandId ?? receivedKeys.single);
        await repo.sync();
        expect(receivedKeys, hasLength(2));
        expect(receivedKeys.toSet(), hasLength(1));
        expect(applied, hasLength(1));
        expect(await repo.pending(), isEmpty);
        expect(repo.rows('rewards'), hasLength(1));
      } finally {
        await repo.db?.close();
        repo.client.close();
        repo.dispose();
        await deleteOwnedTestTemp(folder);
      }
    });
  }

  for (final transport in [false, true]) {
    testWidgets(
      'a queued ${transport ? 'transport' : 'server'} response explains its state and blocks a second save',
      (tester) async {
        final repo = QueuedFormFixture(transport);
        await mountSafety(tester, repo, money: true, scale: 1.5);
        await openSafetyForm(tester, 'create_reward');
        await reveal(tester, find.text('Сохранить'));
        final save = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Сохранить'),
            )
            .onPressed!;
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Запрос сохранён на устройстве'),
          findsOneWidget,
        );
        expect(find.text('Сохранить'), findsNothing);
        expect(repo.writes, hasLength(1));
        save();
        await tester.pumpAndSettle();
        expect(repo.writes, hasLength(1));
        final close = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Закрыть'))
            .onPressed!;
        close();
        close();
        await tester.pumpAndSettle();
        expect(find.text('Добавить награду'), findsOneWidget);
        expect(find.byKey(const ValueKey('field-title')), findsNothing);
        expect(repo.writes, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'queued feedback keeps its explanation and Close visible with large text',
    (tester) async {
      final repo = QueuedFormFixture(false);
      await mountSafety(tester, repo, money: true, scale: 1.5);
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();
      await openSafetyForm(tester, 'create_reward');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      final close = find.widgetWithText(FilledButton, 'Закрыть');
      final explanation = find.textContaining('Запрос сохранён на устройстве');
      expect(close.hitTestable(), findsOneWidget);
      expect(explanation.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(explanation).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
      );
      expect(tester.getRect(close).bottom, lessThanOrEqualTo(640));
      expect(repo.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an account change hides a queued draft without submitting it again',
    (tester) async {
      final repo = QueuedFormFixture(false);
      await mountSafety(tester, repo, money: true);
      await openSafetyForm(tester, 'create_reward');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      repo.token = 'new-owner';
      repo.generation++;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Личные условия первой семьи'), findsNothing);
      expect(find.textContaining('доступ измен'), findsOneWidget);
      expect(repo.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a late confirmed save remains clear after returning from another screen',
    (tester) async {
      final repo = FormSafetyFixture()
        ..saveReply = Completer<Map<String, dynamic>>();
      await mountSafety(tester, repo, money: true);
      await openSafetyForm(tester, 'create_reward');
      await reveal(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Другой экран')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.saveReply!.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(find.text('Другой экран'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Изменения сохранены'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Закрыть'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Закрыть'));
      await tester.pumpAndSettle();
      expect(find.text('Добавить награду'), findsOneWidget);
      expect(repo.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
