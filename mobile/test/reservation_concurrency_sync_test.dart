import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mixed_versions_test.dart' show HistoricalPhone;
import 'review_concurrency_sync_test.dart' show ReviewForeground;

import 'support/owned_temp.dart';
import 'support/live_api_platform.dart';
import 'reward_catalog_concurrency_sync_test.dart'
    show RewardCatalogueTransport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureLiveApiPlatform();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final endpoint = Platform.environment['MYKIDS_MIXED_URL'] ?? '';
  const modes = [
    'mixed',
    'cash',
    'rewards',
    'pending',
    'claimed',
    'lost_reply',
    'stale_cash',
    'confirm_race',
    'cancel_race',
  ];
  final results = <Map<String, dynamic>>[];
  for (final mode in modes) {
    test(
      'shared wallet without restart: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-reservation-clients-',
        );
        final phones = <String, HistoricalPhone>{};
        final services = <ReviewForeground>[];
        try {
          final seeded = await control.post(
            Uri.parse('$endpoint/__test/family'),
            headers: {
              'Authorization':
                  'Bearer ${Platform.environment['MYKIDS_MIXED_CONTROL']!}',
            },
          );
          expect(seeded.statusCode, 200);
          final names = jsonDecode(seeded.body) as Map;
          // A second child session makes a stale wallet reproducible before push delivery.
          for (final actor in ['kid', 'papa', 'mama', 'kid_peer']) {
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
              names[actor == 'kid_peer' ? 'kid' : actor],
              'synthetic-mixed-family-123',
            );
            phone.token = phone.repo.token as String;
            if (actor != 'kid_peer') {
              services.add(ReviewForeground(phone.repo as FamilyRepository));
            }
          }
          final kid = phones['kid']!,
              papa = phones['papa']!,
              mama = phones['mama']!,
              peer = phones['kid_peer']!;
          Future<dynamic> command(
            HistoricalPhone phone,
            String path,
            Map<String, dynamic> body,
          ) {
            phone.activate(endpoint);
            return phone.repo.mutate(path, body);
          }

          final task = await command(papa, '/v1/tasks', {
            'title': 'Стартовые монеты',
            'reward': 100,
            'due_at': '2030-01-01T20:00:00Z',
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
          final price = mode == 'stale_cash' ? 80 : 40;
          final reward = await command(papa, '/v1/rewards', {
            'title': 'Конструктор',
            'price': price,
          });
          final body = {'reward_id': reward['id'], 'expected_price': price};
          String? existing;
          if (const [
            'pending',
            'claimed',
            'confirm_race',
            'cancel_race',
          ].contains(mode)) {
            final request = await command(kid, '/v1/redemptions', {
              'amount': mode.endsWith('_race') ? 60 : 25,
            });
            existing = request['id'] as String;
            if (mode == 'claimed' || mode == 'confirm_race') {
              await command(mama, '/v1/redemptions/$existing/actions', {
                'action': 'claim',
              });
            }
          }
          for (final phone in phones.values) {
            phone.activate(endpoint);
            await phone.repo.sync();
          }
          final before = {
            for (final phone in phones.values) phone.actor: phone.changes,
          };
          Future<int> submit(Map<String, dynamic> values) async {
            try {
              final result = await command(kid, '/v1/redemptions', values);
              return result['queued'] == true ? 202 : 200;
            } on ApiFailure catch (error) {
              return error.status;
            }
          }

          if (mode == 'stale_cash') {
            await command(peer, '/v1/redemptions', body);
            expect(kid.data['balance']['available'], 100);
            expect(await submit({'amount': 60}), 409);
            expect(kid.data['balance']['available'], 20);
            expect(kid.rows('redemptions'), hasLength(1));
            final cache = jsonDecode(
              (await kid.repo.db.query('cache') as List).single['data']
                  as String,
            );
            expect(cache['balance']['available'], 20);
            expect((cache['redemptions'] as List), hasLength(1));
          } else if (mode == 'lost_reply') {
            (kid.transport as RewardCatalogueTransport).loseRequestReply = true;
            expect(await submit({'amount': 60}), 202);
            final pending = (await kid.repo.pending() as List).single as Map;
            await command(peer, '/v1/redemptions', body);
            kid.activate(endpoint);
            await kid.repo.sync();
            expect(kid.transport.commands[pending['id']], 2);
            expect(kid.rows('redemptions'), hasLength(2));
            expect(await kid.repo.pending(), isEmpty);
          } else {
            final attempts = [
              for (var i = 0; i < 8; i++)
                submit(
                  mode == 'rewards' || mode != 'cash' && i.isEven
                      ? body
                      : {'amount': 60},
                ),
            ];
            if (mode == 'confirm_race') {
              attempts.add(
                command(mama, '/v1/redemptions/$existing/actions', {
                  'action': 'confirm',
                }).then((_) => 200),
              );
            } else if (mode == 'cancel_race') {
              attempts.add(
                command(kid, '/v1/redemptions/$existing/actions', {
                  'action': 'cancel',
                }).then((_) => 200),
              );
            }
            final replies = await Future.wait(attempts);
            expect(replies.every((r) => r == 200 || r == 409), isTrue);
            expect(replies.where((r) => r == 200), isNotEmpty);
          }
          // A declined request stays failed and is never replayed automatically.
          final failed = (await kid.repo.pending() as List)
              .where((r) => r['state'] == 'failed')
              .toList();
          final counts = {
            for (final row in failed)
              row['id']: kid.transport.commands[row['id']],
          };
          kid.activate(endpoint);
          await kid.repo.sync();
          for (final row in failed) {
            expect(kid.transport.commands[row['id']], counts[row['id']]);
          }
          Future<void> notify() => Future.wait(
            services.map(
              (service) => service.handleForegroundMessage(
                RemoteMessage(
                  data: {'kind': 'calendar', 'entity_id': reward['id']},
                ),
              ),
            ),
          );
          await notify();
          final requests = kid.rows('redemptions');
          final total = mode == 'confirm_race' ? 40 : 100;
          final reserved = requests
              .where(
                (r) => r['status'] == 'pending' || r['status'] == 'claimed',
              )
              .fold<int>(0, (n, r) => n + r['amount'] as int);
          expect(reserved, inInclusiveRange(0, total));
          expect(
            requests
                .where((r) => r['reward_id'] != null)
                .every((r) => r['amount'] == price),
            isTrue,
          );
          for (final phone in [kid, papa, mama]) {
            expect(phone.rows('redemptions'), requests);
            expect(phone.data['balance']['total'], total);
            expect(phone.data['balance']['reserved'], reserved);
            expect(phone.data['balance']['available'], total - reserved);
            expect(phone.changes, greaterThan(before[phone.actor]!));
            expect(
              phone.rows('ledger'),
              hasLength(mode == 'confirm_race' ? 2 : 1),
            );
          }
          // Complete all remaining requests; previously reserved coins are debited exactly once.
          for (final row in requests.where(
            (r) => r['status'] == 'pending' || r['status'] == 'claimed',
          )) {
            final owner = row['status'] == 'claimed' ? mama : papa;
            final path = '/v1/redemptions/${row['id']}/actions';
            if (row['status'] == 'pending') {
              await command(owner, path, {'action': 'claim'});
            }
            for (var i = 0; i < 3; i++) {
              await command(owner, path, {'action': 'confirm'});
            }
          }
          await notify();
          for (final phone in [kid, papa, mama]) {
            expect(phone.data['balance']['total'], total - reserved);
            expect(phone.data['balance']['available'], total - reserved);
            expect(phone.data['balance']['reserved'], 0);
            expect(
              phone
                  .rows('redemptions')
                  .where(
                    (r) => r['status'] == 'pending' || r['status'] == 'claimed',
                  ),
              isEmpty,
            );
            for (final row
                in phone
                    .rows('redemptions')
                    .where((r) => r['status'] == 'confirmed')) {
              final entries = phone
                  .rows('ledger')
                  .where((r) => r['source_id'] == row['id'])
                  .toList();
              expect(entries, hasLength(1));
              expect(entries.single['actual'], -(row['amount'] as int));
            }
          }
          results.add({
            'mode': mode,
            'reserved_never_exceeds_available_coins': true,
            'three_clients_equal_without_restart': true,
            'pending_count_after_payout': 0,
            'duplicate_debit': false,
            'final_coins': kid.data['balance']['total'],
          });
        } finally {
          for (final service in services) {
            service.dispose();
          }
          for (final phone in phones.values) {
            if (phone.repo.db?.isOpen == true) await phone.close();
          }
          control.close();
          await deleteOwnedTestTemp(folder);
        }
      },
      skip: endpoint.isEmpty
          ? 'Run verify_mixed_versions.py --suite reservations'
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
        'method': 'Three current family repositories and a second child session, isolated TLS API and SQLite; FCM delivery simulated; no physical phones',
        'cases': results,
      }),
    );
  });
}
