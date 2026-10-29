import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
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
  final photo = File('assets/generated/calendar-task.png').readAsBytesSync();
  late Directory folder;
  final repos = <FamilyRepository>[];
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('mykids-update-preserve-');
    await databaseFactory.setDatabasesPath(folder.path);
    FlutterSecureStorage.setMockInitialValues({
      'session': 'synthetic-preserve-token',
      'endpoint': 'https://family.example',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => folder.path,
        );
  });
  tearDown(() async {
    for (final repo in repos) {
      if (repo.db?.isOpen == true) await repo.db!.close();
      repo.client.close();
      repo.dispose();
    }
    repos.clear();
    if (!folder.path.startsWith(Directory.systemTemp.path) ||
        !folder.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('mykids-update-preserve-')) {
      throw StateError('Unexpected test folder');
    }
    await deleteOwnedTestTemp(folder);
  });
  Future<FamilyRepository> open(http.Client client) async {
    final repo = FamilyRepository(client: client);
    repos.add(repo);
    await repo.initialize();
    return repo;
  }

  Future<FamilyRepository> seeded(
    http.Client client, {
    String actor = 'kid',
  }) async {
    final repo = await open(client);
    await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
    repo.snapshot = {
      'user': {
        'id': actor,
        'name': actor,
        'role': actor == 'kid' ? 'child' : 'parent',
      },
      'balance': {'total': 75, 'available': 50, 'reserved': 25},
      'rooms': [
        {'id': 'room', 'unread_count': 2},
      ],
      'tasks': [
        {'id': 'task', 'status': 'submitted'},
      ],
    };
    await repo.cache(repo.snapshot!);
    repo.online = true;
    return repo;
  }

  for (final actor in ['kid', 'papa', 'mama']) {
    test(
      '$actor opens previously downloaded photos after upgrade without internet',
      () async {
        final before = await seeded(
          MockClient((_) async => http.Response.bytes(photo, 200)),
          actor: actor,
        );
        final saved = before.snapshot;
        expect(
          await before.db!.transaction(
            (writer) async =>
                (await writer.rawQuery('PRAGMA synchronous'))
                    .single
                    .values
                    .single,
          ),
          2,
        );
        final cached = await before.attachment('page1');
        await before.db!.close();
        var requests = 0;
        final after = await open(
          MockClient((_) async {
            requests++;
            throw const SocketException('Offline after installation');
          }),
        );
        expect(after.snapshot, saved);
        expect(
          await after.db!.transaction(
            (writer) async =>
                (await writer.rawQuery('PRAGMA synchronous'))
                    .single
                    .values
                    .single,
          ),
          2,
        );
        expect(after.signedIn, true);
        final restored = await after.attachment('page1');
        expect(restored.path, cached.path);
        expect(await restored.readAsBytes(), photo);
        expect(requests, 0);
      },
    );
  }
  for (final failure in ['socket', 'tls', 'timeout', 'client', 'server']) {
    test(
      'cached photo survives $failure while the connection changes',
      () async {
        var fail = false;
        final repo = await seeded(
          MockClient((_) async {
            if (!fail) return http.Response.bytes(photo, 200);
            switch (failure) {
              case 'socket':
                throw const SocketException('Lost network');
              case 'tls':
                throw HandshakeException('Interrupted connection');
              case 'timeout':
                throw TimeoutException('No reply');
              case 'client':
                throw http.ClientException('Interrupted response');
              default:
                return http.Response('Temporary unavailable', 503);
            }
          }),
        );
        final cached = await repo.attachment('page1');
        fail = true;
        final restored = await repo.attachment('page1');
        expect(restored.path, cached.path);
        expect(await restored.readAsBytes(), photo);
        expect(
          await cached.parent
              .list()
              .where((file) => file.path.endsWith('.part'))
              .toList(),
          isEmpty,
        );
      },
    );
  }
  for (final status in [401, 403, 404]) {
    test(
      'explicit server denial $status never falls back to saved media',
      () async {
        var deny = false;
        final repo = await seeded(
          MockClient(
            (_) async => deny
                ? http.Response('Denied', status)
                : http.Response.bytes(photo, 200),
          ),
        );
        final cached = await repo.attachment('page1');
        deny = true;
        await expectLater(
          repo.attachment('page1'),
          throwsA(
            isA<ApiFailure>().having((error) => error.status, 'status', status),
          ),
        );
        expect(await cached.exists(), false);
        if (status == 401) expect(repo.signedIn, false);
      },
    );
  }
  test('a changed family identity cannot read the old photo cache', () async {
    final repo = await seeded(
      MockClient((_) async => http.Response.bytes(photo, 200)),
    );
    await repo.attachment('page1');
    repo.online = false;
    await repo.db!.update('identity', {'tag': 'another-family'});
    await expectLater(repo.attachment('page1'), throwsA(isA<ApiFailure>()));
  });
  test(
    'empty legacy cache is fetched and replaced by the complete photo',
    () async {
      var requests = 0;
      final repo = await seeded(
        MockClient((_) async {
          requests++;
          return http.Response.bytes(photo, 200);
        }),
      );
      final cached = await repo.attachment('page1');
      await cached.writeAsBytes([]);
      repo.online = false;
      expect(await (await repo.attachment('page1')).readAsBytes(), photo);
      expect(requests, 2);
    },
  );
  test('attachment IDs cannot escape their private session folder', () async {
    var requests = 0;
    final repo = await seeded(
      MockClient((_) async {
        requests++;
        return http.Response.bytes(photo, 200);
      }),
    );
    for (final id in ['../outside', '..', 'page/other', 'C:secret']) {
      await expectLater(repo.attachment(id), throwsA(isA<ApiFailure>()));
    }
    expect(requests, 0);
  });
  test('interrupted transfer keeps the existing complete photo', () async {
    var interrupted = false;
    final repo = await seeded(
      MockClient((_) async {
        if (interrupted) {
          throw http.ClientException('Transfer stopped by package replacement');
        }
        return http.Response.bytes(photo, 200);
      }),
    );
    final cached = await repo.attachment('page1');
    interrupted = true;
    expect(await (await repo.attachment('page1')).readAsBytes(), photo);
    expect(await cached.readAsBytes(), photo);
  });
  test('an empty response cannot replace a saved complete photo', () async {
    var empty = false;
    final repo = await seeded(
      MockClient((_) async => http.Response.bytes(empty ? [] : photo, 200)),
    );
    final cached = await repo.attachment('page1');
    empty = true;
    expect(await (await repo.attachment('page1')).readAsBytes(), photo);
    expect(await cached.readAsBytes(), photo);
  });
  test('missing cached photo preserves the original network failure', () async {
    final repo = await seeded(
      MockClient(
        (_) async =>
            throw const SocketException('No network and no saved photo'),
      ),
    );
    repo.online = false;
    await expectLater(
      repo.attachment('missing'),
      throwsA(isA<SocketException>()),
    );
  });
}
