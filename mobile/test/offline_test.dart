import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmanager/workmanager.dart';

import 'support/owned_temp.dart';

class _OfflineJobs extends WorkmanagerPlatform {
  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {}
}

class ControlledStorage extends FlutterSecureStorage {
  final values = <String, String>{
    'session': 'family-test-token',
    'endpoint': 'https://family.example',
  };
  final deleting = Completer<void>(), resume = Completer<void>();
  bool held = false;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == 'session' && !held) {
      held = true;
      deleting.complete();
      await resume.future;
    }
    values.remove(key);
  }
}

class StorageRepository extends FamilyRepository {
  final FlutterSecureStorage controlled;
  StorageRepository(this.controlled, {super.client});
  @override
  FlutterSecureStorage get storage => controlled;
}

class CounterRepository extends FamilyRepository {
  final refreshRequested = Completer<void>();
  CounterRepository({super.client});
  @override
  Future<void> refreshAfterChange() {
    if (!refreshRequested.isCompleted) refreshRequested.complete();
    return super.refreshAfterChange();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory folder;
  late WorkmanagerPlatform originalJobs;
  final databases = <Database>[];
  final snapshot = {
    'server_time': '2026-10-11T12:00:00Z',
    'user': {'id': 'kid', 'role': 'child', 'name': 'Ребёнок'},
    'tasks': <dynamic>[],
    'schedules': <dynamic>[],
  };
  setUp(() async {
    originalJobs = WorkmanagerPlatform.instance;
    WorkmanagerPlatform.instance = _OfflineJobs();
    databases.clear();
    folder = await Directory.systemTemp.createTemp('mykids-test-');
    await databaseFactory.setDatabasesPath(folder.path);
    FlutterSecureStorage.setMockInitialValues({
      'session': 'family-test-token',
      'endpoint': 'https://family.example',
      'variant': 'child',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => folder.path,
        );
  });
  tearDown(() async {
    WorkmanagerPlatform.instance = originalJobs;
    for (final db in databases) {
      if (db.isOpen) await db.close();
    }
    final resolved = p.normalize(folder.absolute.path);
    expect(p.isWithin(Directory.systemTemp.absolute.path, resolved), true);
    expect(p.basename(resolved).startsWith('mykids-test-'), true);
    await deleteOwnedTestTemp(folder);
  });

  Future<FamilyRepository> repository(
    http.Client client, {
    FamilyRepository? instance,
  }) async {
    final repo = instance ?? FamilyRepository(client: client);
    await repo.initialize('child');
    databases.add(repo.db!);
    await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
    await repo.cache(snapshot);
    repo.snapshot = snapshot;
    return repo;
  }

  test('simultaneous refresh callers wait for one shared snapshot', () async {
    final started = Completer<void>(), release = Completer<void>();
    var fetches = 0;
    final repo = await repository(
      MockClient((request) async {
        fetches++;
        started.complete();
        await release.future;
        return http.Response.bytes(utf8.encode(jsonEncode(snapshot)), 200);
      }),
    );
    final first = repo.sync();
    await started.future;
    var joined = false;
    final second = repo.sync().then((_) => joined = true);
    await Future<void>.delayed(Duration.zero);
    expect(joined, false);
    expect(fetches, 1);
    release.complete();
    await Future.wait([first, second]);
    expect(joined, true);
    expect(repo.syncing, false);
  });

  for (final route in [
    '/v1/tasks/task/actions',
    '/v1/redemptions/request/actions',
    '/v1/penalties/fine/approve',
    '/v1/grades',
    '/v1/messages/message/receipt',
  ]) {
    test(
      'confirmed $route refreshes counters after a stale background response',
      () async {
        final oldStarted = Completer<void>(), releaseOld = Completer<void>();
        final freshStarted = Completer<void>(),
            releaseFresh = Completer<void>();
        final old = {
          ...snapshot,
          'balance': {'total': 0, 'reserved': 0, 'available': 0},
        };
        final fresh = {
          ...snapshot,
          'tasks': [
            {'id': 'task', 'status': 'completed'},
          ],
          'balance': {'total': 150, 'reserved': 25, 'available': 125},
          'rooms': [
            {'id': 'room', 'unread_count': 0},
          ],
          'redemptions': [
            {'id': 'request', 'status': 'confirmed'},
          ],
          'penalties': [
            {'id': 'fine', 'status': 'applied'},
          ],
        };
        var fetches = 0, writes = 0;
        final client = MockClient((request) async {
          if (request.method == 'POST') {
            writes++;
            return http.Response('{"ok":true}', 200);
          }
          fetches++;
          if (fetches == 1) {
            oldStarted.complete();
            await releaseOld.future;
            return http.Response.bytes(utf8.encode(jsonEncode(old)), 200);
          }
          freshStarted.complete();
          await releaseFresh.future;
          return http.Response.bytes(utf8.encode(jsonEncode(fresh)), 200);
        });
        final traced = CounterRepository(client: client);
        final repo = await repository(client, instance: traced);
        repo.online = true;
        repo.snapshot = {
          ...snapshot,
          'balance': {'available': 50},
        };
        final background = repo.sync();
        await oldStarted.future;
        var finished = false;
        final change =
            (route.endsWith('/receipt')
                    ? repo
                          .request(
                            route,
                            method: 'POST',
                            key: 'read-test',
                            body: {'status': 'read'},
                          )
                          .then((_) => repo.refreshAfterChange())
                    : repo.mutate(route, {'action': 'approve'}).then((_) {}))
                .then((_) => finished = true);
        await traced.refreshRequested.future;
        expect(finished, false);
        releaseOld.complete();
        await freshStarted.future;
        expect(repo.snapshot!['balance']['available'], 50);
        expect(finished, false);
        releaseFresh.complete();
        await Future.wait([background, change]);
        expect(repo.snapshot, fresh);
        expect(
          jsonDecode((await repo.db!.query('cache')).single['data'] as String),
          fresh,
        );
        expect(fetches, 2);
        expect(writes, 1);
        expect(await repo.pending(), isEmpty);
      },
    );
  }

  test('old sync completion cannot end a new account refresh', () async {
    final oldStarted = Completer<void>(), releaseOld = Completer<void>();
    final newStarted = Completer<void>(), releaseNew = Completer<void>();
    final repo = await repository(
      MockClient((request) async {
        final old =
            request.headers['Authorization'] == 'Bearer family-test-token';
        (old ? oldStarted : newStarted).complete();
        await (old ? releaseOld : releaseNew).future;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(
              old
                  ? snapshot
                  : {
                      ...snapshot,
                      'user': {'id': 'new-child', 'role': 'child'},
                    },
            ),
          ),
          200,
        );
      }),
    );
    final first = repo.sync();
    await oldStarted.future;
    repo.generation++;
    repo.token = 'new-token';
    await repo.db!.update('identity', {'tag': repo.sessionTag}, where: 'id=1');
    final second = repo.sync();
    await newStarted.future;
    releaseOld.complete();
    await first;
    expect(repo.syncing, true);
    releaseNew.complete();
    await second;
    expect(repo.userId, 'new-child');
    expect(repo.syncing, false);
  });

  test(
    'offline completion survives app restart and reuses the same command ID',
    () async {
      final offline = await repository(
        MockClient((request) async => throw const SocketException('offline')),
      );
      final result = await offline.mutate('/v1/tasks/task/submissions', {
        'task_version': 1,
        'marked_at': '2026-10-11T10:00:00Z',
      }, offlineSubmission: true);
      expect(result['queued'], true);
      final key = (await offline.pending()).single['id'];
      await offline.db!.close();
      final fresh = FamilyRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/submissions')) {
            expect(request.headers['Idempotency-Key'], key);
            return http.Response('{"accepted":true}', 200);
          }
          return http.Response.bytes(utf8.encode(jsonEncode(snapshot)), 200);
        }),
      );
      await fresh.initialize('child');
      databases.add(fresh.db!);
      expect(fresh.snapshot!['user']['id'], 'kid');
      await fresh.sync();
      expect(await fresh.pending(), isEmpty);
      expect(fresh.online, true);
      await fresh.db!.close();
    },
  );

  test('legacy rejected calls retire without discarding task or money commands or another identity', () async {
    final repo = await repository(
      MockClient((_) async => http.Response('{}', 200)),
    );
    for (final entry in {
      'call': '/v1/calls/finished/actions',
      'start': '/v1/rooms/room/calls',
      'money': '/v1/redemptions/reward/actions',
      'task': '/v1/tasks/task/submissions',
      'foreign': '/v1/calls/foreign/actions',
    }.entries) {
      await repo.db!.insert('outbox', {
        'id': entry.key,
        'path': entry.value,
        'method': 'POST',
        'body': '{}',
        'files': '[]',
        'state': 'failed',
        'error': 'Звонок завершён',
        'auth_tag': entry.key == 'foreign' ? 'other-account' : repo.sessionTag,
      });
    }
    expect((await repo.pending()).map((r) => r['id']), ['money', 'task']);
    expect((await repo.db!.query('outbox')).map((r) => r['id']), [
      'money',
      'task',
      'foreign',
    ]);
  });

  test('new rejected call is reported but does not become an unfixable pending action', () async {
    final repo = await repository(
      MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'detail': 'Звонок завершён'})),
          409,
        ),
      ),
    );
    repo.online = true;
    await expectLater(
      repo.mutate('/v1/calls/finished/actions', {'action': 'leave'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(await repo.pending(), isEmpty);
    await expectLater(
      repo.mutate('/v1/redemptions/reward/actions', {'action': 'confirm'}),
      throwsA(isA<ApiFailure>()),
    );
    expect((await repo.pending()).single['state'], 'failed');
  });

  test('network loss while hanging up retains one retry, terminal retry failure retires it', () async {
    var disconnected = true;
    final repo = await repository(
      MockClient((request) async {
        if (request.url.path == '/v1/snapshot') {
          return http.Response.bytes(utf8.encode(jsonEncode(snapshot)), 200);
        }
        if (disconnected) throw const SocketException('offline');
        return http.Response.bytes(
          utf8.encode(jsonEncode({'detail': 'Звонок завершён'})),
          409,
        );
      }),
    );
    repo.online = true;
    final result = await repo.mutate('/v1/calls/finished/actions', {
      'action': 'leave',
    });
    expect(result['queued'], true);
    expect((await repo.pending()).single['state'], 'pending');
    disconnected = false;
    await repo.sync();
    expect(await repo.pending(), isEmpty);
    expect(repo.online, true);
  });

  test(
    'conflicting family permissions refresh before reporting the stale action',
    () async {
      final updated = {
        ...snapshot,
        'members': [
          {'id': 'relative', 'active': 0, 'permissions_revision': 'b' * 64},
        ],
      };
      var changes = 0, refreshes = 0;
      final repo = await repository(
        MockClient((request) async {
          if (request.url.path == '/v1/snapshot') {
            refreshes++;
            return http.Response.bytes(utf8.encode(jsonEncode(updated)), 200);
          }
          changes++;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'detail':
                    'Права доступа изменились. Проверьте разрешения заново',
              }),
            ),
            409,
          );
        }),
      );
      repo.online = true;
      await expectLater(
        repo.mutate('/v1/members/relative', {
          'view_tasks': true,
          'expected_revision': 'a' * 64,
        }, method: 'PATCH'),
        throwsA(isA<ApiFailure>()),
      );
      expect(changes, 1);
      expect(refreshes, 1);
      expect(repo.rows('members').single['active'], 0);
      expect(repo.rows('members').single['permissions_revision'], 'b' * 64);
      expect((await repo.pending()).single['state'], 'failed');
      await repo.sync();
      expect(
        changes,
        1,
        reason: 'A rejected permission edit must never retry automatically',
      );
    },
  );

  test('uncertain access change stays unconfirmed and cannot restore a newer revocation', () async {
    var disconnected = true;
    final body = {'view_tasks': true, 'expected_revision': 'a' * 64};
    final updated = {
      ...snapshot,
      'members': [
        {'id': 'relative', 'active': 0, 'permissions_revision': 'b' * 64},
      ],
    };
    final repo = await repository(
      MockClient((request) async {
        if (request.url.path == '/v1/snapshot') {
          return http.Response.bytes(utf8.encode(jsonEncode(updated)), 200);
        }
        expect(jsonDecode(request.body), body);
        if (disconnected) throw const SocketException('offline');
        return http.Response.bytes(
          utf8.encode(jsonEncode({'detail': 'Права доступа изменились'})),
          409,
        );
      }),
    );
    repo.online = true;
    final result = await repo.mutate(
      '/v1/members/relative',
      body,
      method: 'PATCH',
    );
    expect(result['queued'], true);
    expect(result['message'], contains('ещё не подтверждено'));
    expect((await repo.pending()).single['state'], 'pending');
    disconnected = false;
    await repo.sync();
    expect((await repo.pending()).single['state'], 'failed');
    expect(repo.rows('members').single['active'], 0);
  });

  test(
    'calendar changes queue without a network attempt and survive restart',
    () async {
      var attempts = 0;
      final offline = await repository(
        MockClient((_) async {
          attempts++;
          throw const SocketException('offline');
        }),
      );
      final result = await offline.mutate(
        '/v1/schedules/calendar-event',
        {
          'title': 'Перенесённое занятие',
          'date': '2026-10-12',
          'weekdays': [],
          'start': '15:00',
          'end': '16:00',
          'reminder_minutes': 30,
        },
        method: 'PUT',
        offlineSubmission: true,
      );
      expect(result['queued'], true);
      expect(attempts, 0);
      final key = (await offline.pending()).single['id'];
      await offline.db!.close();
      var sent = 0;
      final fresh = FamilyRepository(
        client: MockClient((request) async {
          if (request.method == 'PUT') {
            expect(request.url.path, '/v1/schedules/calendar-event');
            expect(request.headers['Idempotency-Key'], key);
            expect(jsonDecode(request.body)['reminder_minutes'], 30);
            sent++;
            return http.Response('{"ok":true}', 200);
          }
          return http.Response.bytes(utf8.encode(jsonEncode(snapshot)), 200);
        }),
      );
      await fresh.initialize('child');
      databases.add(fresh.db!);
      await fresh.sync();
      expect(sent, 1);
      expect(await fresh.pending(), isEmpty);
    },
  );

  test(
    'parallel background and foreground sync send one leased command',
    () async {
      final held = Completer<void>();
      var sends = 0;
      final repo = await repository(
        MockClient((request) async {
          sends++;
          await held.future;
          return http.Response('{"accepted":true}', 200);
        }),
      );
      await repo.db!.insert('outbox', {
        'id': 'one',
        'path': '/v1/tasks/task/submissions',
        'method': 'POST',
        'body': '{}',
        'files': '[]',
        'state': 'pending',
        'auth_tag': repo.sessionTag,
      });
      final row = (await repo.pending()).single;
      final first = repo.sendOutbox(row);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final duplicate = await repo.sendOutbox(row);
      expect(duplicate['queued'], true);
      held.complete();
      await first;
      expect(sends, 1);
      await repo.db!.close();
    },
  );

  test('late background response cannot restore cache after logout', () async {
    final response = Completer<http.Response>();
    final repo = await repository(MockClient((request) => response.future));
    final refresh = repo.sync();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.logout(remote: false);
    response.complete(
      http.Response.bytes(utf8.encode(jsonEncode(snapshot)), 200),
    );
    await refresh;
    expect(await repo.db!.query('cache'), isEmpty);
    expect(repo.signedIn, false);
    await repo.db!.close();
  });

  test('late old-account rejection cannot log out the new account', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final repo = await repository(
      MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer family-test-token');
        started.complete();
        return response.future;
      }),
    );
    repo.online = true;
    final sending = repo.mutate('/v1/tasks', {'title': 'Old action'});
    final failure = expectLater(sending, throwsA(isA<ApiFailure>()));
    await started.future;
    repo.generation++;
    repo.token = 'new-account-token';
    await repo.db!.delete('outbox');
    await repo.db!.update('identity', {'tag': repo.sessionTag});
    await repo.db!.insert('cache', {
      'id': 1,
      'data': '{"new":true}',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    response.complete(http.Response('{"detail":"Old access expired"}', 401));
    await failure;
    expect(repo.token, 'new-account-token');
    expect(repo.online, true);
    expect((await repo.db!.query('cache')).single['data'], '{"new":true}');
    await repo.db!.close();
  });

  test('a foreground session signs out after background expiration clears identity', () async {
    final repo = await repository(
      MockClient((_) async => http.Response('{"detail":"Expired"}', 401)),
    );
    await repo.db!.delete('identity');
    await repo.db!.delete('cache');
    await repo.sync();
    expect(repo.signedIn, false);
    expect(repo.snapshot, isNull);
    await repo.db!.close();
  });

  test('old logout cannot delete photos saved by the new account', () async {
    final repo = await repository(
      MockClient((_) async => http.Response('{}', 200)),
    );
    final oldFolder = Directory(
      p.join(folder.path, 'attachments', repo.sessionTag),
    );
    await oldFolder.create(recursive: true);
    await File(p.join(oldFolder.path, 'old.jpg')).writeAsBytes([1]);
    final entered = Completer<void>(), resume = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            entered.complete();
            await resume.future;
            return folder.path;
          },
        );
    final leaving = repo.logout(remote: false);
    await entered.future;
    repo.generation++;
    repo.token = 'new-account-token';
    await repo.storage.write(key: 'session', value: repo.token);
    await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
    final newFile = File(
      p.join(folder.path, 'attachments', repo.sessionTag, 'new.jpg'),
    );
    await newFile.parent.create(recursive: true);
    await newFile.writeAsBytes([2]);
    resume.complete();
    await leaving;
    expect(await oldFolder.exists(), false);
    expect(await newFile.readAsBytes(), [2]);
    expect(repo.token, 'new-account-token');
    expect(await repo.storage.read(key: 'session'), 'new-account-token');
    await repo.db!.close();
  });

  test(
    'stale background plans and logout cannot change the current device alarms',
    () async {
      final repo = await repository(
        MockClient((_) async => http.Response('{}', 200)),
      );
      final newTag = sha256.convert(utf8.encode('new-account')).toString();
      await repo.db!.update('identity', {'tag': newTag});
      var changed = false;
      await repo.guardDeviceUpdate(() async => changed = true);
      expect(changed, false);
      repo.token = null;
      await repo.storage.write(key: 'session', value: 'new-account');
      await repo.guardDeviceUpdate(() async => changed = true);
      expect(changed, false);
      await repo.db!.close();
    },
  );

  test(
    'authenticated refresh recovers a login interrupted before local commit',
    () async {
      final repo = await repository(
        MockClient(
          (_) async =>
              http.Response.bytes(utf8.encode(jsonEncode(snapshot)), 200),
        ),
      );
      await repo.db!.delete('identity');
      await repo.db!.delete('cache');
      await repo.sync();
      expect(repo.online, true);
      expect(repo.signedIn, true);
      expect((await repo.db!.query('identity')).single['tag'], repo.sessionTag);
      expect((await repo.db!.query('cache')), hasLength(1));
      await repo.db!.close();
    },
  );

  test(
    'retry uses persisted photo IDs instead of an earlier captured row',
    () async {
      final repo = await repository(
        MockClient((request) async {
          expect(jsonDecode(request.body)['attachment_ids'], [
            'uploaded-photo',
          ]);
          return http.Response('{"accepted":true}', 200);
        }),
      );
      await repo.db!.insert('outbox', {
        'id': 'photo-retry',
        'path': '/v1/tasks/task/submissions',
        'method': 'POST',
        'body': '{}',
        'files': '["already-uploaded.jpg"]',
        'state': 'pending',
        'auth_tag': repo.sessionTag,
      });
      final captured = (await repo.pending()).single;
      await repo.db!.update(
        'outbox',
        {'body': '{"attachment_ids":["uploaded-photo"]}', 'files': '[]'},
        where: 'id=?',
        whereArgs: ['photo-retry'],
      );
      await repo.sendOutbox(captured);
      expect(await repo.pending(), isEmpty);
    },
  );

  test('old account response cannot replace a newer account cache', () async {
    final repo = await repository(
      MockClient((request) async => http.Response('{}', 200)),
    );
    final newTag = sha256.convert(utf8.encode('different-account')).toString();
    await repo.db!.update('identity', {'tag': newTag});
    await repo.db!.insert('cache', {
      'id': 1,
      'data': '{"new":true}',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await repo.cache(snapshot);
    expect((await repo.db!.query('cache')).single['data'], '{"new":true}');
    await repo.db!.close();
  });

  test(
    'closing a background connection leaves the foreground database open',
    () async {
      final foreground = await repository(
        MockClient((request) async => http.Response('{}', 200)),
      );
      final background = FamilyRepository(
        client: MockClient((request) async => http.Response('{}', 200)),
      );
      await background.initialize('child');
      databases.add(background.db!);
      await background.db!.close();
      expect((await foreground.db!.query('cache')).single['id'], 1);
    },
  );

  test(
    'background credential deletion finishes before a new login persists',
    () async {
      final storage = ControlledStorage();
      final old = StorageRepository(
        storage,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await old.initialize('child');
      databases.add(old.db!);
      await old.db!.insert('identity', {'id': 1, 'tag': old.sessionTag});
      final current = StorageRepository(
        storage,
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode(
                request.url.path == '/v1/login'
                    ? {'token': 'new-account-token'}
                    : {
                        ...snapshot,
                        'user': {'id': 'new-user', 'role': 'parent'},
                      },
              ),
            ),
            200,
          ),
        ),
      );
      await current.initialize('child');
      databases.add(current.db!);
      final leaving = old.logout(remote: false);
      await storage.deleting.future;
      var completed = false;
      final login = current
          .login('https://family.example', 'new-user', 'synthetic-password')
          .then((_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(completed, false);
      storage.resume.complete();
      await leaving;
      await login;
      expect(storage.values['session'], 'new-account-token');
      expect(
        (await current.db!.query('identity')).single['tag'],
        current.sessionTag,
      );
      expect(current.userId, 'new-user');
      expect(current.online, true);
      await old.db!.close();
      await current.db!.close();
    },
  );
}
