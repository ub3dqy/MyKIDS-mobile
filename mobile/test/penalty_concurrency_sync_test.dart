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

class PenaltyTransport extends MixedTransport {
  bool losePenaltyReply = false;
  final penaltyKeys = <String>[];
  PenaltyTransport(super.inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final penalty =
        request.method == 'POST' &&
        request.url.path.startsWith('/v1/penalties/');
    if (penalty) {
      penaltyKeys.add(request.headers['Idempotency-Key']!);
    }
    final response = await super.send(request);
    if (penalty && losePenaltyReply) {
      losePenaltyReply = false;
      await response.stream.drain<void>();
      throw const SocketException(
        'Synthetic penalty acknowledgement lost after commit',
      );
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
  for (final mode in [
    'task_burst',
    'grade_burst',
    'task_lost_reply',
    'grade_lost_reply',
    'task_replay',
    'grade_replay',
    'task_waive_race',
    'grade_waive_race',
    'task_failure_race',
    'task_stale',
  ]) {
    test(
      'one penalty and three clients: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-penalty-clients-',
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
              PenaltyTransport(client()),
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
            Map<String, dynamic> body, {
            String method = 'POST',
          }) async {
            phone.activate(endpoint);
            return phone.repo.mutate(path, body, method: method);
          }

          final earned = await command(papa, '/v1/tasks', {
            'title': 'Монеты для проверки штрафа',
            'due_at': '2030-01-01T15:00:00Z',
            'is_required': false,
            'reward': 30,
          });
          final earnedId = (earned['ids'] as List).single;
          await command(kid, '/v1/tasks/$earnedId/submissions', {
            'task_version': 1,
            'marked_at': DateTime.now().toUtc().toIso8601String(),
          });
          await command(papa, '/v1/tasks/$earnedId/actions', {
            'action': 'approve',
            'task_version': 1,
          });
          final source = mode.startsWith('grade') ? 'grade' : 'task';
          String sourceId;
          if (source == 'task') {
            final created = await command(papa, '/v1/tasks', {
              'title': 'Проверка одновременного штрафа',
              'due_at': '2020-01-01T12:00:00Z',
              'penalty': 500,
              'reward': 0,
              'is_required': true,
            });
            sourceId = (created['ids'] as List).single as String;
          } else {
            final subject = await command(papa, '/v1/subjects', {
              'name': 'Математика',
            });
            await command(papa, '/v1/grade-rules', {
              'amounts': {'2': -500},
            }, method: 'PUT');
            final grade = await command(papa, '/v1/grades', {
              'subject_id': subject['id'],
              'date': '2026-10-16',
              'grade': 2,
            });
            sourceId = grade['id'] as String;
          }
          for (final phone in phones.values) {
            await phone.repo.sync();
            expect(phone.data['balance']['total'], 30);
            expect(phone.rows('penalties').single['status'], 'pending');
          }
          final id = papa.rows('penalties').single['id'] as String;
          final changesBefore = {
            for (final phone in phones.values) phone.actor: phone.changes,
          };
          Future<dynamic> action(HistoricalPhone phone, String decision) =>
              command(phone, '/v1/penalties/$id/$decision', {});
          if (mode.endsWith('_burst')) {
            final replies = await Future.wait([
              for (var i = 0; i < 8; i++)
                action(i.isEven ? papa : mama, 'approve'),
            ]);
            expect(replies.every((r) => r['status'] == 'applied'), true);
          } else if (mode.endsWith('_lost_reply')) {
            (papa.transport as PenaltyTransport).losePenaltyReply = true;
            final reply = await action(papa, 'approve');
            expect(reply['queued'], true);
            final pending = (await papa.repo.pending() as List).single as Map;
            expect((await action(mama, 'approve'))['status'], 'applied');
            await papa.repo.sync();
            expect(await papa.repo.pending(), isEmpty);
            expect(papa.transport.commands[pending['id']], 2);
          } else if (mode.endsWith('_replay')) {
            await action(papa, 'approve');
            final key = (papa.transport as PenaltyTransport).penaltyKeys.single;
            await papa.repo.db.insert('outbox', <String, Object?>{
              'id': key,
              'path': '/v1/penalties/$id/approve',
              'method': 'POST',
              'body': '{}',
              'files': '[]',
              'state': 'pending',
              'auth_tag': papa.repo.sessionTag,
            });
            await papa.repo.sync();
            expect(papa.transport.commands[key], 2);
            expect(await papa.repo.pending(), isEmpty);
          } else if (mode.endsWith('_waive_race')) {
            final replies = await Future.wait([
              action(papa, 'approve'),
              action(mama, 'waive'),
            ]);
            expect(replies.map((r) => r['status']).toSet(), hasLength(1));
          } else if (mode == 'task_failure_race') {
            await Future.wait([
              action(papa, 'approve'),
              command(mama, '/v1/tasks/$sourceId/actions', {
                'action': 'not_completed',
                'task_version': 1,
              }),
            ]);
          } else {
            expect(
              papa
                  .rows('tasks')
                  .firstWhere((t) => t['id'] == sourceId)['status'],
              'assigned',
            );
            await command(kid, '/v1/tasks/$sourceId/submissions', {
              'task_version': 1,
              'marked_at': DateTime.now().toUtc().toIso8601String(),
            });
            await expectLater(
              action(papa, 'approve'),
              throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
            );
            // No notification is delivered before checking the rejected parent's screen.
            expect(
              papa
                  .rows('tasks')
                  .firstWhere((t) => t['id'] == sourceId)['status'],
              'submitted',
            );
            expect(
              papa.rows('tasks').where((t) => t['status'] == 'submitted'),
              hasLength(1),
            );
            expect(papa.data['balance']['total'], 30);
            expect(
              (await papa.repo.pending() as List).single['state'],
              'failed',
            );
            await command(mama, '/v1/tasks/$sourceId/actions', {
              'action': 'approve',
              'task_version': 1,
            });
            expect(
              (await papa.repo.pending() as List).single['state'],
              'failed',
            );
          }
          // Real foreground refresh handler; external notification delivery is simulated.
          await Future.wait(
            services.map(
              (service) => service.handleForegroundMessage(
                RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
              ),
            ),
          );
          final row = kid.rows('penalties').single;
          final applied = row['status'] == 'applied';
          if (!mode.endsWith('_waive_race') && mode != 'task_stale') {
            expect(applied, true);
          }
          if (mode == 'task_stale') {
            expect(row['status'], 'waived');
          }
          for (final phone in phones.values) {
            expect(phone.rows('penalties').single, row);
            expect(phone.data['balance']['total'], applied ? -470 : 30);
            expect(phone.data['balance']['available'], applied ? -470 : 30);
            expect(phone.data['balance']['reserved'], 0);
            expect(
              phone.rows('penalties').where((p) => p['status'] == 'pending'),
              isEmpty,
            );
            expect(
              phone.rows('tasks').where((t) => t['status'] == 'submitted'),
              isEmpty,
            );
            final entries = phone
                .rows('ledger')
                .where((e) => e['source_id'] == sourceId)
                .toList();
            expect(entries, hasLength(applied ? 1 : 0));
            if (applied) {
              expect(entries.single['actual'], -500);
            }
            if (source == 'task' && applied) {
              expect(
                phone
                    .rows('tasks')
                    .firstWhere((t) => t['id'] == sourceId)['status'],
                'not_completed',
              );
            }
            expect(phone.changes, greaterThan(changesBefore[phone.actor]!));
          }
          results.add({
            'mode': mode,
            'penalty_status': row['status'],
            'coins': applied ? -470 : 30,
            'debits': applied ? 1 : 0,
            'pending_penalties': 0,
            'three_clients_equal_without_restart': true,
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
          ? 'Run verify_mixed_versions.py --suite penalties'
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
        'expected': 10,
        'passed': results.length,
        'cases': results,
      }),
      flush: true,
    );
  });
}
