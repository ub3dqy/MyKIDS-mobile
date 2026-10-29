import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mykids_family/repository.dart' as current;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/versions/repository_0_1_38.dart' as v38;
import 'fixtures/versions/repository_0_1_42.dart' as v42;
import 'support/live_api_platform.dart';
import 'support/owned_temp.dart';

// A single process runs three independent historical repositories. Their
// transports, databases and media folders are distinct; only the test API is
// shared. These are original old sources, not today's code with older labels.
class MixedTransport extends http.BaseClient {
  final http.Client inner;
  bool offline = false;
  final commands = <String, int>{};
  final bodies = <String, String>{};
  MixedTransport(this.inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw const SocketException('Synthetic phone offline');
    final key = request.headers['Idempotency-Key'];
    if (key != null) {
      commands.update(key, (n) => n + 1, ifAbsent: () => 1);
      if (request is http.Request) bodies[key] = request.body;
    }
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

class HistoricalPhone {
  final String actor, version;
  final Directory folder;
  final MixedTransport transport;
  final dynamic repo;
  String? token;
  int changes = 0;
  HistoricalPhone(this.actor, this.version, this.folder, this.transport)
    : repo = switch (version) {
        '0.1.38' => v38.FamilyRepository(client: transport),
        '0.1.42' => v42.FamilyRepository(client: transport),
        _ => current.FamilyRepository(client: transport),
      } {
    repo.addListener(() => changes++);
  }

  Map<String, dynamic> get data =>
      Map<String, dynamic>.from(repo.snapshot as Map);
  List<Map<String, dynamic>> rows(String name) =>
      (repo.rows(name) as List).cast<Map<String, dynamic>>();

  void activate(String endpoint) {
    FlutterSecureStorage.setMockInitialValues({
      'endpoint': endpoint,
      'session': ?token,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => folder.path,
        );
  }

  Future<void> initialize(String endpoint) async {
    activate(endpoint);
    await databaseFactory.setDatabasesPath(folder.path);
    await repo.initialize();
  }

  Future<void> close() async {
    await repo.db.close();
    transport.close();
    repo.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureLiveApiPlatform();
  // This suite explicitly talks to its isolated TLS fixture. The binding's
  // default HTTP mock otherwise answers every real request with status 400.
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final currentVersion = RegExp(
    r'^version:\s+(\d+\.\d+\.\d+)',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
  final versions = ['0.1.38', '0.1.42', currentVersion];
  const actors = ['kid', 'papa', 'mama'];
  final endpoint = Platform.environment['MYKIDS_MIXED_URL'] ?? '';
  final results = <Map<String, dynamic>>[];
  final skipped = endpoint.isEmpty
      ? 'Run scripts/verify_mixed_versions.py for the isolated real API'
      : false;
  final sourceManifest = jsonDecode(
    File('test/fixtures/versions/manifest.json').readAsStringSync(),
  ) as Map;

  test('historical sources have not been modified', () {
    for (final fixture in sourceManifest['fixtures'] as List) {
      expect(
        sha256
            .convert(File(fixture['path'] as String).readAsBytesSync())
            .toString(),
        fixture['sha256'],
      );
    }
  });

  for (final kidVersion in versions) {
    for (final papaVersion in versions) {
      for (final mamaVersion in versions) {
        final matrix = [kidVersion, papaVersion, mamaVersion];
        test(
          'mixed phones ${matrix.join('/')}',
          () async {
            final fixture = Directory(
              Platform.environment['MYKIDS_MIXED_FOLDER']!,
            );
            final context = SecurityContext(withTrustedRoots: false)
              ..setTrustedCertificates('${fixture.path}/ca.pem');
            http.Client client() => IOClient(HttpClient(context: context));
            final controller = client();
            final phones = <String, HistoricalPhone>{};
            final local = await Directory.systemTemp.createTemp(
              'mykids-mixed-clients-',
            );
            try {
              final response = await controller.post(
                Uri.parse('$endpoint/__test/family'),
                headers: {
                  'Authorization':
                      'Bearer ${Platform.environment['MYKIDS_MIXED_CONTROL']!}',
                },
              );
              expect(response.statusCode, 200);
              final names = jsonDecode(response.body) as Map;
              for (var index = 0; index < actors.length; index++) {
                final actor = actors[index];
                final folder = await Directory('${local.path}/$actor').create();
                final phone = HistoricalPhone(
                  actor,
                  matrix[index],
                  folder,
                  MixedTransport(client()),
                );
                phones[actor] = phone;
                await phone.initialize(endpoint);
                await phone.repo.login(
                  endpoint,
                  names[actor],
                  'synthetic-mixed-family-123',
                );
                phone.token = phone.repo.token as String;
                expect(phone.repo.role, actor == 'kid' ? 'child' : 'parent');
              }
              final kid = phones['kid']!,
                  papa = phones['papa']!,
                  mama = phones['mama']!;
              Future<dynamic> command(
                HistoricalPhone phone,
                String path,
                Map<String, dynamic> body, {
                String method = 'POST',
                List<String> files = const [],
                bool queued = false,
              }) async {
                phone.activate(endpoint);
                return phone.repo.mutate(
                  path,
                  body,
                  method: method,
                  files: files,
                  offlineSubmission: queued,
                );
              }

              Future<void> refresh() async {
                for (final phone in phones.values) {
                  phone.activate(endpoint);
                  final revision = phone.changes;
                  await phone.repo.sync();
                  expect(phone.repo.online, true);
                  expect(phone.changes, greaterThan(revision));
                }
              }

              void balances(int total, {int reserved = 0}) {
                for (final phone in phones.values) {
                  expect(phone.data['balance']['total'], total);
                  expect(phone.data['balance']['reserved'], reserved);
                  expect(phone.data['balance']['available'], total - reserved);
                }
              }

              final photoHashes = <String, String>{};
              var total = 0;
              for (final count in [6, 5, 4]) {
                final result = await command(papa, '/v1/tasks', {
                  'title': 'Математика $count из 6',
                  'due_at': '2030-01-01T15:00:00Z',
                  'is_required': false,
                  'require_photo': true,
                  'required_photos': 2,
                  'reward_options': {
                    'total': 6,
                    'tiers': [
                      {'minimum': 6, 'coins': 50},
                      {'minimum': 5, 'coins': 25},
                    ],
                  },
                });
                final id = (result['ids'] as List).single as String;
                await refresh();
                expect(
                  kid
                      .rows('tasks')
                      .singleWhere((t) => t['id'] == id)['required_photos'],
                  2,
                );
                kid.activate(endpoint);
                final files = <String>[];
                for (var page = 0; page < 2; page++) {
                  files.add(
                    await kid.repo.keepFile('${fixture.path}/page$page.png')
                        as String,
                  );
                }
                kid.transport.offline = true;
                kid.repo.online = false;
                final queued = await command(
                  kid,
                  '/v1/tasks/$id/submissions',
                  {
                    'task_version': 1,
                    'marked_at': DateTime.now().toUtc().toIso8601String(),
                  },
                  files: files,
                  queued: true,
                );
                expect(queued['queued'], true);
                final outbox = (await kid.repo.pending() as List).single as Map;
                kid.transport.offline = false;
                await refresh();
                expect(await kid.repo.pending(), isEmpty);
                expect(kid.transport.commands[outbox['id']], 1);
                for (final phone in phones.values) {
                  expect(
                    phone
                        .rows('tasks')
                        .where((t) => t['status'] == 'submitted')
                        .length,
                    1,
                  );
                  final submission = phone
                      .rows('submissions')
                      .singleWhere((s) => s['task_id'] == id);
                  final ids = (jsonDecode(
                    submission['attachment_ids'] as String,
                  ) as List).cast<String>();
                  expect(ids, hasLength(2));
                  for (final photoId in ids) {
                    phone.activate(endpoint);
                    final photo = await phone.repo.attachment(photoId) as File;
                    final hash = sha256
                        .convert(await photo.readAsBytes())
                        .toString();
                    expect(hash, photoHashes.putIfAbsent(photoId, () => hash));
                  }
                }
                // Replay the original acknowledged outbox row with its UUID and
                // uploaded IDs. This models a lost reply across a version change.
                final raw = await kid.repo.db.query(
                  'outbox',
                  where: 'id=?',
                  whereArgs: [outbox['id']],
                ) as List;
                expect(raw, isEmpty);
                await kid.repo.db.insert('outbox', <String, Object?>{
                  ...outbox,
                  'body': kid.transport.bodies[outbox['id']]!,
                  'files': '[]',
                  'lease_until': 0,
                });
                await refresh();
                expect(kid.transport.commands[outbox['id']], 2);
                for (final phone in phones.values) {
                  expect(
                    phone.rows('submissions').where((s) => s['task_id'] == id),
                    hasLength(1),
                  );
                }
                final reviewer = count == 5 ? mama : papa;
                await command(reviewer, '/v1/tasks/$id/actions', {
                  'action': 'approve',
                  'task_version': 1,
                  'completed_count': count,
                });
                await command(
                  identical(reviewer, papa) ? mama : papa,
                  '/v1/tasks/$id/actions',
                  {
                    'action': 'approve',
                    'task_version': 1,
                    'completed_count': 6,
                  },
                );
                total += count == 6
                    ? 50
                    : count == 5
                    ? 25
                    : 0;
                await refresh();
                balances(total);
                for (final phone in phones.values) {
                  expect(
                    phone
                        .rows('tasks')
                        .where((t) => t['status'] == 'submitted'),
                    isEmpty,
                  );
                  expect(
                    phone
                        .rows('tasks')
                        .singleWhere((t) => t['id'] == id)['completed_count'],
                    count,
                  );
                  expect(
                    phone
                        .rows('ledger')
                        .where((e) => e['source_id'] == id)
                        .length,
                    count >= 5 ? 1 : 0,
                  );
                }
              }
              final reward = await command(mama, '/v1/rewards', {
                'title': 'Конструктор',
                'price': 25,
                'available': true,
              });
              await refresh();
              final request = await command(kid, '/v1/redemptions', {
                'reward_id': reward['id'],
                'expected_price': 25,
              });
              await refresh();
              balances(75, reserved: 25);
              for (final phone in phones.values) {
                expect(
                  phone
                      .rows('redemptions')
                      .where((r) => r['status'] == 'pending'),
                  hasLength(1),
                );
              }
              await command(papa, '/v1/redemptions/${request['id']}/actions', {
                'action': 'claim',
              });
              await command(papa, '/v1/redemptions/${request['id']}/actions', {
                'action': 'confirm',
              });
              await refresh();
              balances(50);
              for (final phone in phones.values) {
                expect(
                  phone
                      .rows('redemptions')
                      .where(
                        (r) => ['pending', 'claimed'].contains(r['status']),
                      ),
                  isEmpty,
                );
              }
              final room = kid
                  .rows('rooms')
                  .singleWhere((r) => r['kind'] == 'family')['id'];
              final sent = await command(kid, '/v1/rooms/$room/messages', {
                'text': 'Готово',
              });
              await refresh();
              expect(
                papa
                    .rows('rooms')
                    .singleWhere((r) => r['id'] == room)['unread_count'],
                1,
              );
              expect(
                mama
                    .rows('rooms')
                    .singleWhere((r) => r['id'] == room)['unread_count'],
                1,
              );
              await command(papa, '/v1/messages/${sent['id']}/receipt', {
                'status': 'read',
              });
              await refresh();
              expect(
                papa
                    .rows('rooms')
                    .singleWhere((r) => r['id'] == room)['unread_count'],
                0,
              );
              expect(
                mama
                    .rows('rooms')
                    .singleWhere((r) => r['id'] == room)['unread_count'],
                1,
              );

              // Upgrade each remaining old repository in place, retaining its
              // actual schema-2/3 database, credentials, photos and queued action.
              for (final actor in actors) {
                final before = phones[actor]!;
                before.activate(endpoint);
                before.transport.offline = true;
                before.repo.online = false;
                final extra = await command(
                  before,
                  '/v1/messages/${sent['id']}/receipt',
                  {'status': 'delivered'},
                  queued: true,
                );
                expect(extra['queued'], true);
                final pending =
                    (await before.repo.pending() as List).single as Map;
                final cached = before.data;
                await before.close();
                final after = HistoricalPhone(
                  actor,
                  currentVersion,
                  before.folder,
                  MixedTransport(client()),
                )..token = before.token;
                phones[actor] = after;
                await after.initialize(endpoint);
                expect(after.data, cached);
                final restored =
                    (await after.repo.pending() as List).single as Map;
                for (final key in ['id', 'path', 'body', 'files', 'auth_tag']) {
                  expect(restored[key], pending[key]);
                }
                after.transport.offline = true;
                after.repo.online = false;
                for (final photoId in photoHashes.keys) {
                  final photo = await after.repo.attachment(photoId) as File;
                  expect(
                    sha256.convert(await photo.readAsBytes()).toString(),
                    photoHashes[photoId],
                  );
                }
                after.transport.offline = false;
                await after.repo.sync();
                expect(await after.repo.pending(), isEmpty);
                expect(after.transport.commands[pending['id']], 1);
                expect(after.data['balance']['total'], 50);
                final schema =
                    await after.repo.db.rawQuery('PRAGMA user_version') as List;
                expect((schema.single as Map)['user_version'], 3);
              }
              results.add({
                'versions': Map.fromIterables(actors, matrix),
                'tasks': 3,
                'reward_results': [50, 25, 0],
                'photo_hashes_equal': true,
                'photos': photoHashes.length,
                'read_counter': '1 -> 0',
                'reward_balance': '75 -> 50',
                'old_databases_upgraded': true,
                'queued_uuid_body_and_auth_retained': true,
                'all_actors_converged': true,
              });
            } finally {
              for (final phone in phones.values) {
                if (phone.repo.db?.isOpen == true) await phone.close();
              }
              controller.close();
              await deleteOwnedTestTemp(local);
            }
          },
          skip: skipped,
          timeout: const Timeout(Duration(minutes: 3)),
        );
      }
    }
  }
  tearDownAll(() async {
    if (endpoint.isEmpty) return;
    final target = Platform.environment['MYKIDS_MIXED_REPORT']!;
    await File(target).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'utc': DateTime.now().toUtc().toIso8601String(),
        'method': 'Original historical Dart repositories and current real API over isolated TLS; no physical phones or old APK UI',
        'sources': sourceManifest,
        'passed': results.length,
        'expected': 27,
        'cases': results,
      }),
      flush: true,
    );
  });
}
