import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mixed_versions_test.dart' show HistoricalPhone;

import 'support/owned_temp.dart';
import 'support/live_api_platform.dart';
import 'review_concurrency_sync_test.dart'
    show ReviewTransport, ReviewForeground;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureLiveApiPlatform();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final endpoint = Platform.environment['MYKIDS_MIXED_URL'] ?? '';
  final results = <Map<String, dynamic>>[];
  for (final mode in [
    'both_parents',
    'stale_claim',
    'handoff',
    'lost_reply',
    'cancel_vs_claim',
    'confirm_vs_release',
    'owner_replay',
    'confirm_vs_reject',
  ]) {
    test(
      'one redemption and three clients: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-redemption-clients-',
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
              ReviewTransport(client()),
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
          final kid = phones['kid']!,
              papa = phones['papa']!,
              mama = phones['mama']!;
          Future<dynamic> command(
            HistoricalPhone phone,
            String path,
            Map<String, dynamic> body,
          ) async {
            phone.activate(endpoint);
            return phone.repo.mutate(path, body);
          }

          final task = await command(papa, '/v1/tasks', {
            'title': 'Монеты для проверки выдачи',
            'due_at': '2030-01-01T15:00:00Z',
            'is_required': false,
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
          final reward = await command(papa, '/v1/rewards', {
            'title': 'Конструктор',
            'price': 25,
            'available': true,
          });
          final redemption = await command(kid, '/v1/redemptions', {
            'reward_id': reward['id'],
            'expected_price': 25,
          });
          final id = redemption['id'] as String;
          final path = '/v1/redemptions/$id/actions';
          Future<dynamic> action(HistoricalPhone phone, String action) =>
              command(phone, path, {'action': action});
          Future<int> attempt(HistoricalPhone phone, String name) async {
            try {
              await action(phone, name);
              return 200;
            } on ApiFailure catch (error) {
              return error.status;
            }
          }

          for (final phone in phones.values) {
            await phone.repo.sync();
            expect(phone.rows('redemptions').single['status'], 'pending');
            expect(phone.data['balance']['total'], 100);
            expect(phone.data['balance']['reserved'], 25);
          }
          if (mode == 'both_parents') {
            final claim = await Future.wait([
              for (var i = 0; i < 8; i++)
                attempt(i.isEven ? papa : mama, 'claim'),
            ]);
            expect(claim.where((code) => code == 200), hasLength(4));
            expect(claim.where((code) => code == 409), hasLength(4));
            final confirm = await Future.wait([
              for (var i = 0; i < 8; i++)
                attempt(i.isEven ? papa : mama, 'confirm'),
            ]);
            expect(confirm.where((code) => code == 200), hasLength(4));
            expect(confirm.where((code) => code == 403), hasLength(4));
          } else if (mode == 'stale_claim') {
            await action(mama, 'claim');
            await action(mama, 'confirm');
            expect(await attempt(papa, 'claim'), 409);
            expect(papa.rows('redemptions').single['status'], 'confirmed');
            expect(papa.data['balance']['total'], 75);
          } else if (mode == 'handoff') {
            await action(papa, 'claim');
            await action(papa, 'release');
            await action(mama, 'claim');
            expect(await attempt(papa, 'confirm'), 403);
            expect(
              papa.rows('redemptions').single['claimed_by'],
              mama.repo.userId,
            );
            expect(papa.repo.signedIn, true);
            await action(mama, 'confirm');
            expect(await attempt(papa, 'confirm'), 403);
            expect(papa.rows('redemptions').single['status'], 'confirmed');
            expect(papa.data['balance']['total'], 75);
          } else if (mode == 'lost_reply') {
            await action(papa, 'claim');
            (papa.transport as ReviewTransport).loseReviewReply = true;
            final queued = await action(papa, 'confirm');
            expect(queued['queued'], true);
            final pending = (await papa.repo.pending() as List).single as Map;
            expect(await attempt(mama, 'claim'), 409);
            expect(mama.rows('redemptions').single['status'], 'confirmed');
            await papa.repo.sync();
            expect(await papa.repo.pending(), isEmpty);
            expect(papa.transport.commands[pending['id']], 2);
          } else if (mode == 'cancel_vs_claim') {
            final replies = await Future.wait([
              attempt(kid, 'cancel'),
              attempt(papa, 'claim'),
            ]);
            expect(replies..sort(), [200, 409]);
          } else if (mode == 'owner_replay') {
            await action(papa, 'claim');
            await Future.wait([
              for (var i = 0; i < 8; i++) action(papa, 'confirm'),
            ]);
            final original = papa.transport.bodies.entries.firstWhere(
              (entry) =>
                  (jsonDecode(entry.value) as Map)['action'] == 'confirm',
            );
            await papa.repo.db.insert('outbox', <String, Object?>{
              'id': original.key,
              'path': path,
              'method': 'POST',
              'body': original.value,
              'files': '[]',
              'state': 'pending',
              'auth_tag': papa.repo.sessionTag,
            });
            await papa.repo.sync();
            expect(papa.transport.commands[original.key], 2);
            expect(await papa.repo.pending(), isEmpty);
          } else {
            await action(papa, 'claim');
            final other = mode == 'confirm_vs_release' ? 'release' : 'reject';
            final replies = await Future.wait([
              attempt(papa, 'confirm'),
              attempt(papa, other),
            ]);
            expect(replies.where((code) => code == 200), hasLength(1));
            expect(
              replies.every((code) => [200, 403, 409].contains(code)),
              true,
            );
          }
          // Real foreground refresh, with notification delivery simulated.
          await Future.wait(
            services.map(
              (service) => service.handleForegroundMessage(
                RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
              ),
            ),
          );
          final request = kid.rows('redemptions').single;
          final status = request['status'] as String;
          final paid = status == 'confirmed';
          final reserved = ['pending', 'claimed'].contains(status) ? 25 : 0;
          if ([
            'both_parents',
            'stale_claim',
            'handoff',
            'lost_reply',
            'owner_replay',
          ].contains(mode)) {
            expect(status, 'confirmed');
          }
          for (final phone in phones.values) {
            expect(phone.rows('redemptions').single, request);
            expect(phone.data['balance']['total'], paid ? 75 : 100);
            expect(phone.data['balance']['reserved'], reserved);
            expect(
              phone.data['balance']['available'],
              (paid ? 75 : 100) - reserved,
            );
            final entries = phone
                .rows('ledger')
                .where((entry) => entry['source_id'] == id)
                .toList();
            expect(entries, hasLength(paid ? 1 : 0));
            if (paid) expect(entries.single['actual'], -25);
            expect(
              phone
                  .rows('redemptions')
                  .where(
                    (row) => ['pending', 'claimed'].contains(row['status']),
                  ),
              hasLength(reserved > 0 ? 1 : 0),
            );
          }
          results.add({
            'mode': mode,
            'status': status,
            'coins': paid ? 75 : 100,
            'reserved': reserved,
            'debits': paid ? 1 : 0,
            'open_requests': reserved > 0 ? 1 : 0,
            'three_clients_equal_without_restart': true,
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
          ? 'Run verify_mixed_versions.py --suite redemptions'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  tearDownAll(() async {
    if (endpoint.isEmpty) return;
    await File(Platform.environment['MYKIDS_MIXED_REPORT']!).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'utc': DateTime.now().toUtc().toIso8601String(),
        'method': 'Three independent clients and real isolated HTTPS API; FCM delivery simulated; no physical phones',
        'expected': 8,
        'passed': results.length,
        'cases': results,
      }),
      flush: true,
    );
  });
}
