import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mixed_versions_test.dart' show HistoricalPhone, MixedTransport;
import 'review_concurrency_sync_test.dart' show ReviewForeground;

import 'support/owned_temp.dart';
import 'support/live_api_platform.dart';

class RewardCatalogueTransport extends MixedTransport {
  bool loseReply = false;
  bool loseRequestReply = false;
  RewardCatalogueTransport(super.inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final catalogue =
        request.method != 'GET' && request.url.path.startsWith('/v1/rewards/');
    final response = await super.send(request);
    if (request.method == 'POST' &&
        request.url.path == '/v1/redemptions' &&
        loseRequestReply) {
      loseRequestReply = false;
      await response.stream.drain<void>();
      throw const SocketException(
        'Synthetic committed reward request reply lost',
      );
    }
    if (catalogue && loseReply) {
      loseReply = false;
      await response.stream.drain<void>();
      throw const SocketException('Synthetic committed catalogue reply lost');
    }
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureLiveApiPlatform();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final endpoint = Platform.environment['MYKIDS_MIXED_URL'] ?? '';
  final results = <Map<String, dynamic>>[];
  const modes = [
    'edit_edit',
    'edit_delete',
    'delete_delete',
    'lost_edit',
    'lost_delete',
    'stale_price',
    'stale_delete',
    'stale_goal',
    'pending_edit',
    'pending_delete',
    'request_first_increase',
    'request_first_decrease',
    'request_first_hide',
    'request_first_delete',
    'change_first_increase',
    'change_first_decrease',
    'change_first_hide',
    'change_first_delete',
    'request_race_increase',
    'request_race_delete',
    'request_lost_increase',
    'request_lost_delete',
    'legacy_request_increase',
  ];
  for (final mode in modes) {
    test(
      'catalogue changes on three live clients: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-catalogue-clients-',
        );
        final phones = <String, HistoricalPhone>{};
        final services = <ReviewForeground>[];
        try {
          final response = await control.post(
            Uri.parse('$endpoint/__test/family'),
            headers: {
              'Authorization':
                  'Bearer ${Platform.environment['MYKIDS_MIXED_CONTROL']!}',
            },
          );
          expect(response.statusCode, 200);
          final names = jsonDecode(response.body) as Map;
          for (final actor in ['kid', 'papa', 'mama']) {
            final directory = await Directory('${folder.path}/$actor').create();
            final phone = HistoricalPhone(
              actor,
              'current',
              directory,
              RewardCatalogueTransport(client()),
            );
            phones[actor] = phone;
            await phone.initialize(endpoint);
            await phone.repo.login(
              endpoint,
              names[actor],
              'synthetic-mixed-family-123',
            );
            phone.token = phone.repo.token as String;
            services.add(ReviewForeground(phone.repo as FamilyRepository));
          }
          final papa = phones['papa']!,
              mama = phones['mama']!,
              kid = phones['kid']!;
          Future<dynamic> command(
            HistoricalPhone phone,
            String path,
            Map<String, dynamic> body, {
            String method = 'POST',
          }) {
            phone.activate(endpoint);
            return phone.repo.mutate(path, body, method: method);
          }

          final task = await command(papa, '/v1/tasks', {
            'title': 'Стартовые монеты',
            'due_at': '2030-01-01T20:00:00Z',
            'reward': 100,
          });
          final taskId = (task['ids'] as List).single;
          await command(kid, '/v1/tasks/$taskId/submissions', {
            'task_version': 1,
            'marked_at': DateTime.now().toUtc().toIso8601String(),
          });
          await command(papa, '/v1/tasks/$taskId/actions', {
            'action': 'approve',
            'task_version': 1,
          });
          final gift = await command(papa, '/v1/rewards', {
            'title': 'Конструктор',
            'description': 'Награда',
            'price': 25,
          });
          final id = gift['id'] as String, path = '/v1/rewards/${gift['id']}';
          await command(kid, '/v1/goal', {'reward_id': id}, method: 'PUT');
          String? request;
          final requestRace =
              mode.startsWith('request_') ||
              mode.startsWith('change_first_') ||
              mode.startsWith('legacy_request_');
          if (!mode.startsWith('stale_') && !requestRace) {
            final submitted = await command(kid, '/v1/redemptions', {
              'reward_id': id,
              'expected_price': 25,
            });
            request = submitted['id'] as String;
          }
          for (final phone in phones.values) {
            await phone.repo.sync();
          }
          final revision = papa.rows('rewards').single['revision'];
          final before = {
            for (final phone in phones.values) phone.actor: phone.changes,
          };
          Future<int> change(HistoricalPhone phone, String op) async {
            final body = <String, dynamic>{
              'expected_revision': revision,
              if (op == 'edit') ...{
                'title': 'Изменено ${phone.actor}',
                'description': 'Новое описание',
                'price': 60,
                'available': true,
              },
              if (const ['increase', 'decrease', 'hide'].contains(op)) ...{
                'title': 'Новые условия',
                'description': 'Новое описание',
                'price': op == 'decrease'
                    ? 10
                    : op == 'increase'
                    ? 60
                    : 25,
                'available': op != 'hide',
              },
            };
            try {
              final reply = await command(
                phone,
                path,
                body,
                method: op == 'delete' ? 'DELETE' : 'PUT',
              );
              return reply['queued'] == true ? 202 : 200;
            } on ApiFailure catch (error) {
              return error.status;
            }
          }

          if (requestRace) {
            final op = mode.split('_').last;
            Future<int> submit() async {
              try {
                final result = await command(kid, '/v1/redemptions', {
                  'reward_id': id,
                  if (!mode.startsWith('legacy_')) 'expected_price': 25,
                });
                if (result['queued'] == true) return 202;
                request = result['id'] as String;
                return 200;
              } on ApiFailure catch (error) {
                return error.status;
              }
            }

            if (mode.startsWith('request_lost_')) {
              (kid.transport as RewardCatalogueTransport).loseRequestReply =
                  true;
              expect(await submit(), 202);
              final queued = (await kid.repo.pending() as List).single as Map;
              expect(await change(mama, op), 200);
              kid.activate(endpoint);
              await kid.repo.sync();
              expect(kid.transport.commands[queued['id']], 2);
              expect(await kid.repo.pending(), isEmpty);
              request = kid.rows('redemptions').single['id'] as String;
            } else {
              int status;
              if (mode.startsWith('request_first_')) {
                status = await submit();
                expect(status, 200);
                expect(await change(mama, op), 200);
              } else if (mode.startsWith('request_race_')) {
                final replies = await Future.wait([submit(), change(mama, op)]);
                status = replies.first;
                expect(replies.last, 200);
                expect(status, anyOf(200, op == 'delete' ? 404 : 409));
              } else {
                expect(await change(mama, op), 200);
                status = await submit();
                expect(status, op == 'delete' ? 404 : 409);
              }
              if (status != 200) {
                // The rejected child refreshes before the notification is delivered.
                expect(kid.rows('rewards'), mama.rows('rewards'));
                expect(kid.rows('redemptions'), isEmpty);
                expect(kid.data['balance']['reserved'], 0);
                kid.activate(endpoint);
                final commandsBeforeSync = Map<String, int>.from(
                  kid.transport.commands,
                );
                await kid.repo.sync();
                expect(kid.rows('redemptions'), isEmpty);
                expect(kid.transport.commands, commandsBeforeSync);
                expect(
                  (await kid.repo.pending() as List).every(
                    (r) => r['state'] == 'failed',
                  ),
                  isTrue,
                );
              }
            }
          } else if (mode.startsWith('lost_')) {
            (papa.transport as RewardCatalogueTransport).loseReply = true;
            expect(await change(papa, mode.substring(5)), 202);
            final pending = (await papa.repo.pending() as List).single as Map;
            await papa.repo.sync();
            expect(papa.transport.commands[pending['id']], 2);
            expect(await papa.repo.pending(), isEmpty);
          } else if (mode.startsWith('stale_')) {
            expect(
              await change(papa, mode == 'stale_price' ? 'edit' : 'delete'),
              200,
            );
            kid.activate(endpoint);
            await expectLater(
              kid.repo.mutate(
                mode == 'stale_goal' ? '/v1/goal' : '/v1/redemptions',
                {
                  'reward_id': id,
                  if (mode != 'stale_goal') 'expected_price': 25,
                },
                method: mode == 'stale_goal' ? 'PUT' : 'POST',
              ),
              throwsA(
                isA<ApiFailure>().having(
                  (e) => e.status,
                  'status',
                  mode == 'stale_price' ? 409 : 404,
                ),
              ),
            );
            expect(kid.rows('rewards'), papa.rows('rewards'));
            expect(kid.rows('redemptions'), isEmpty);
            expect(kid.data['balance']['reserved'], 0);
          } else if (mode.startsWith('pending_')) {
            expect(await change(mama, mode.substring(8)), 200);
          } else {
            final pair = mode.split('_');
            final replies = await Future.wait([
              for (var i = 0; i < 8; i++)
                change(i.isEven ? papa : mama, pair[i % 2]),
            ]);
            expect(replies.where((r) => r == 200), hasLength(1));
            expect(replies.where((r) => r == 409 || r == 404), hasLength(7));
            expect(papa.rows('rewards'), mama.rows('rewards'));
          }
          Future<void> notify() => Future.wait(
            services.map(
              (service) => service.handleForegroundMessage(
                RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
              ),
            ),
          );
          await notify();
          final catalogue = kid.rows('rewards');
          for (final phone in phones.values) {
            expect(phone.rows('rewards'), catalogue);
            expect(phone.data['balance']['total'], 100);
            expect(phone.data['balance']['reserved'], request == null ? 0 : 25);
            expect(
              phone.data['balance']['available'],
              request == null ? 100 : 75,
            );
            expect(phone.rows('ledger'), hasLength(1));
            expect(phone.changes, greaterThan(before[phone.actor]!));
            if (catalogue.isEmpty) {
              expect(phone.data['goal'], isNull);
            } else {
              expect(
                catalogue.single['price'],
                mode.endsWith('_decrease')
                    ? 10
                    : mode.endsWith('_hide')
                    ? 25
                    : 60,
              );
              expect(
                catalogue.single['available'],
                mode.endsWith('_hide') ? 0 : 1,
              );
              expect(phone.data['goal']['reward_id'], id);
            }
            if (request != null) {
              final agreed = phone.rows('redemptions').single;
              expect(agreed['amount'], 25);
              expect(agreed['title'], 'Конструктор');
              expect(agreed['status'], 'pending');
              expect(agreed['reward_id'], catalogue.isEmpty ? null : id);
            }
          }
          if (request != null) {
            await command(papa, '/v1/redemptions/$request/actions', {
              'action': 'claim',
            });
            await Future.wait([
              for (var i = 0; i < 8; i++)
                command(papa, '/v1/redemptions/$request/actions', {
                  'action': 'confirm',
                }),
            ]);
            await notify();
            for (final phone in phones.values) {
              expect(phone.data['balance']['total'], 75);
              expect(phone.data['balance']['available'], 75);
              expect(phone.data['balance']['reserved'], 0);
              expect(
                phone
                    .rows('redemptions')
                    .where(
                      (r) =>
                          r['status'] == 'pending' || r['status'] == 'claimed',
                    ),
                isEmpty,
              );
              final debits = phone
                  .rows('ledger')
                  .where((r) => r['source_id'] == request)
                  .toList();
              expect(debits, hasLength(1));
              expect(debits.single['actual'], -25);
            }
          }
          results.add({
            'mode': mode,
            'three_clients_equal_without_restart': true,
            'catalogue_count': catalogue.length,
            'coins': kid.data['balance']['total'],
            'agreed_amount_preserved': true,
            'double_debit': false,
          });
        } finally {
          for (final service in services) {
            service.dispose();
          }
          for (final phone in phones.values) {
            if (phone.repo.db?.isOpen == true) {
              await phone.close();
            }
          }
          control.close();
          await deleteOwnedTestTemp(folder);
        }
      },
      skip: endpoint.isEmpty
          ? 'Run verify_mixed_versions.py --suite reward-catalogue'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  tearDownAll(() async {
    if (endpoint.isEmpty) return;
    await File(Platform.environment['MYKIDS_MIXED_REPORT']!).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'utc': DateTime.now().toUtc().toIso8601String(),
        'expected': modes.length,
        'passed': results.length,
        'method': 'Three actual repositories and SQLite databases, isolated HTTPS API; simulated FCM; no physical phones',
        'cases': results,
      }),
    );
  });
}
