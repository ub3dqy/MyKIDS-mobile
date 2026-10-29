import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/event_editor.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/school_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/owned_temp.dart';

class LeasedDatabase extends Fake implements Database {
  final Database inner;
  final committed = Completer<void>(), resume = Completer<void>();
  LeasedDatabase(this.inner);
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    final result = await inner.transaction(action, exclusive: exclusive);
    committed.complete();
    await resume.future;
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => inner.query(
    table,
    where: where,
    whereArgs: whereArgs,
    columns: columns,
    limit: limit,
  );
  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => inner.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      inner.delete(table, where: where, whereArgs: whereArgs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'profile change after a durable lease prevents the old command',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final folder = await Directory.systemTemp.createTemp('mykids-audit-');
      final requests = <Map<String, dynamic>>[];
      final repo = FamilyRepository(
        client: MockClient((request) async {
          requests.add({
            'path': request.url.path,
            'authorization': request.headers['Authorization'],
            'body': jsonDecode(request.body),
          });
          return http.Response('{"ids":["created-in-new-family"]}', 200);
        }),
      );
      Database? inner;
      try {
        inner = await openDatabase('${folder.path}/audit.sqlite');
        await inner.execute(
          'CREATE TABLE identity(id INTEGER PRIMARY KEY,tag TEXT)',
        );
        await inner.execute(
          'CREATE TABLE outbox(id TEXT PRIMARY KEY,path TEXT,method TEXT,body TEXT,files TEXT,state TEXT,error TEXT,lease_until INTEGER DEFAULT 0,auth_tag TEXT,lease_owner TEXT DEFAULT \'\')',
        );
        repo.endpoint = 'https://audit.example';
        repo.token = 'old-family-parent';
        await inner.insert('identity', {'id': 1, 'tag': repo.sessionTag});
        await inner.insert('outbox', {
          'id': 'old-family-create',
          'path': '/v1/tasks',
          'method': 'POST',
          'body': jsonEncode({
            'title': 'Private task from old family',
            'due_at': '2030-01-01T12:00:00Z',
            'reward': 0,
            'penalty': 0,
            'is_required': false,
          }),
          'files': '[]',
          'state': 'pending',
          'auth_tag': repo.sessionTag,
        });
        final row = (await inner.query('outbox')).single;
        final leased = LeasedDatabase(inner);
        repo.db = leased;
        final sending = repo.sendOutbox(row);
        await leased.committed.future;
        repo.generation++;
        repo.token = 'new-family-parent';
        await inner.delete('outbox');
        await inner.update('identity', {'tag': repo.sessionTag});
        final failure = expectLater(sending, throwsA(isA<ApiFailure>()));
        leased.resume.complete();
        await failure;
        expect(requests, isEmpty);
        expect(repo.token, 'new-family-parent');
      } finally {
        await inner?.close();
        repo.client.close();
        repo.dispose();
        if (!folder.absolute.path.startsWith(
          Directory.systemTemp.absolute.path,
        )) {
          throw StateError('Unexpected test folder');
        }
        await deleteOwnedTestTemp(folder);
      }
    },
  );
  test('account change during upload cannot send the old submission', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final folder = await Directory.systemTemp.createTemp('mykids-audit-');
    final sent = <String?>[];
    final uploaded = Completer<void>(), resume = Completer<void>();
    final repo = FamilyRepository(
      client: MockClient((request) async {
        if (request.url.path == '/v1/attachments') {
          expect(request.headers['Authorization'], 'Bearer old-account');
          uploaded.complete();
          await resume.future;
          return http.Response('{"id":"old-account-photo"}', 200);
        }
        sent.add(request.headers['Authorization']);
        return http.Response('{"accepted":true}', 200);
      }),
    );
    try {
      repo.db = await openDatabase('${folder.path}/audit.sqlite');
      await repo.db!.execute(
        'CREATE TABLE identity(id INTEGER PRIMARY KEY,tag TEXT)',
      );
      await repo.db!.execute(
        'CREATE TABLE outbox(id TEXT PRIMARY KEY,path TEXT,method TEXT,body TEXT,files TEXT,state TEXT,error TEXT,lease_until INTEGER DEFAULT 0,auth_tag TEXT,lease_owner TEXT DEFAULT \'\')',
      );
      repo.endpoint = 'https://audit.example';
      repo.token = 'old-account';
      await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
      await repo.db!.insert('outbox', {
        'id': 'audit-command',
        'path': '/v1/tasks/old-task/submissions',
        'method': 'POST',
        'body': '{}',
        'files': jsonEncode(['${folder.path}/missing-audit-photo.jpg']),
        'state': 'pending',
        'auth_tag': repo.sessionTag,
      });
      await File('${folder.path}/missing-audit-photo.jpg')
          .writeAsBytes([1, 2, 3]);
      final sending = repo.sendOutbox((await repo.pending()).single);
      final failure = expectLater(sending, throwsA(isA<ApiFailure>()));
      await uploaded.future;
      // Logout/login has replaced both credentials and the durable identity.
      repo.generation++;
      repo.token = 'new-account';
      await repo.db!.delete('outbox');
      await repo.db!.update('identity', {'tag': repo.sessionTag});
      resume.complete();
      await failure;
      expect(sent, isEmpty);
      expect(repo.token, 'new-account');
    } finally {
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
      if (!folder.absolute.path.startsWith(
        Directory.systemTemp.absolute.path,
      )) {
        throw StateError('Unexpected test folder');
      }
      await deleteOwnedTestTemp(folder);
    }
  });
  testWidgets('new calendar events enable the promised default reminder', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    final snapshot = <String, dynamic>{
      'family': {'timezone': 'Europe/Moscow'},
    };
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarEditor(
          snapshot: snapshot,
          day: familyClock(snapshot),
          onSave: (body) async {
            saved = body;
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('event-title')),
      'Audit lesson',
    );
    await tester.tap(find.byKey(const ValueKey('event-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!['reminder_minutes'], 30);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('tasks opened from grades react to changed repository', (
    tester,
  ) async {
    final repo = FamilyRepository();
    repo.token = 'audit';
    repo.online = true;
    final instant = DateTime.now().toUtc();
    repo.snapshot = {
      'user': {'id': 'kid', 'role': 'child', 'name': 'Test child'},
      'family': {'timezone': 'Europe/Moscow'},
      'members': <dynamic>[],
      'schedules': <dynamic>[],
      'schedule_exceptions': <dynamic>[],
      'tasks': [
        {
          'id': 'task',
          'title': 'Before audit',
          'description': '',
          'due_at': instant.toIso8601String(),
          'reward': 0,
          'penalty': 0,
          'is_required': 0,
          'status': 'assigned',
          'require_photo': 1,
          'financial_approved': 1,
          'version': 1,
          'note': '',
          'author_id': 'parent',
          'reviewer_id': null,
        },
      ],
      'submissions': <dynamic>[],
    };
    final day = familyClock(repo.snapshot, instant);
    await tester.pumpWidget(
      MaterialApp(
        home: SchoolScreen(
          repository: repo,
          gradesOnly: true,
          initialDay: day,
          perform: (action) async {
            await action();
          },
        ),
      ),
    );
    final button = find.text('Отправить результат с фотографией');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Before audit'), findsOneWidget);
    repo.snapshot!['tasks'][0]['title'] = 'After audit';
    repo.notifyListeners();
    await tester.pump();
    expect(find.text('Before audit'), findsNothing);
    expect(find.text('After audit'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo.client.close();
    repo.dispose();
  });
  for (final value in <int?>[null, 0, 45]) {
    testWidgets('editing preserves reminder $value', (tester) async {
      Map<String, dynamic>? saved;
      final data = <String, dynamic>{
        'family': {'timezone': 'Europe/Moscow'},
      };
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarEditor(
            snapshot: data,
            day: familyClock(data),
            initial: {
              'title': 'Событие',
              'date': '2030-01-01',
              'start': '09:00',
              'end': '10:00',
              'reminder_minutes': value,
            },
            onSave: (body) async => saved = body,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();
      expect(saved?['reminder_minutes'], value);
      expect(saved, isNotNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'a collapsed invalid reminder opens its field and blocks saving',
    (tester) async {
      Map<String, dynamic>? saved;
      final data = <String, dynamic>{
        'family': {'timezone': 'Europe/Moscow'},
      };
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarEditor(
            snapshot: data,
            day: familyClock(data),
            onSave: (body) async => saved = body,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-title')),
        'Событие',
      );
      await tester.ensureVisible(find.text('Напоминание'));
      await tester.tap(find.text('Напоминание'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('event-reminder')),
        'bad',
      );
      await tester.ensureVisible(find.text('Напоминание'));
      await tester.tap(find.text('Напоминание'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('event-reminder')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.byKey(const ValueKey('event-reminder')), findsOneWidget);
      expect(find.text('Укажите от 0 до 10080 минут'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
