import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mixed_versions_test.dart' show HistoricalPhone, MixedTransport;
import 'support/live_api_platform.dart';
import 'support/owned_temp.dart';

class FinancialTransport extends MixedTransport {
  bool loseReply = false;
  FinancialTransport(super.inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await super.send(request);
    if (loseReply && request.url.path.endsWith('/actions')) {
      loseReply = false;
      await response.stream.drain<void>();
      throw const SocketException(
        'Synthetic loss after actual financial approval commit',
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
  const modes = [
    'stale_terms',
    'legacy_terms',
    'lost_reply',
    'offline_terms',
    'repeat_template',
    'repeat_override',
  ];
  for (final mode in modes) {
    test(
      'parental consent with four actual TLS clients: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-financial-clients-',
        );
        final phones = <String, HistoricalPhone>{};
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
          for (final actor in ['papa', 'mama', 'kid', 'grandma']) {
            final phone = HistoricalPhone(
              actor,
              actor == 'mama' ? '0.1.42' : 'current',
              await Directory('${folder.path}/$actor').create(),
              FinancialTransport(client()),
            );
            phones[actor] = phone;
            await phone.initialize(endpoint);
            await phone.repo.login(
              endpoint,
              names[actor],
              'synthetic-mixed-family-123',
            );
            phone.token = phone.repo.token as String;
          }
          final papa = phones['papa']!,
              mama = phones['mama']!,
              grandma = phones['grandma']!;
          Future<void> refresh(HistoricalPhone phone) async {
            phone.activate(endpoint);
            await phone.repo.sync();
          }

          Future<Map<String, dynamic>> change(
            HistoricalPhone phone,
            String path,
            Map<String, dynamic> body, {
            String method = 'POST',
          }) async {
            phone.activate(endpoint);
            return Map<String, dynamic>.from(
              await phone.repo.mutate(path, body, method: method),
            );
          }

          final member = papa
              .rows('members')
              .singleWhere((m) => m['role'] == 'relative');
          await change(papa, '/v1/members/${member['id']}', {
            'create_tasks': true,
            'view_tasks': true,
            'review_tasks': true,
            'expected_revision': member['permissions_revision'],
          }, method: 'PATCH');
          await refresh(grandma);
          final repeat = mode.startsWith('repeat_');
          final created = await change(grandma, '/v1/tasks', {
            'title': 'Проверяемые условия',
            'reward': 30,
            'penalty': 15,
            'is_required': true,
            'due_at': DateTime.now()
                .add(const Duration(days: 1))
                .toUtc()
                .toIso8601String(),
            if (repeat) 'weekdays': [1, 2, 3, 4, 5, 6, 7],
          });
          final ids = (created['ids'] as List).cast<String>();
          await refresh(papa);
          await refresh(mama);
          Map<String, dynamic> task(HistoricalPhone phone, String id) =>
              phone.rows('tasks').singleWhere((t) => t['id'] == id);
          Future<void> editTask(String id, int reward) async {
            await refresh(grandma);
            final current = task(grandma, id);
            await change(grandma, '/v1/tasks/$id', {
              for (final k in [
                'title',
                'description',
                'due_at',
                'penalty',
                'reviewer_id',
                'program_id',
                'subject_id',
                'planned_start',
                'planned_end',
                'reminder_minutes',
                'reward_options',
                'required_photos',
              ])
                k: current[k],
              'reward': reward,
              'is_required': current['is_required'] == 1,
              'require_photo': current['require_photo'] == 1,
              'task_version': current['version'],
            }, method: 'PUT');
          }

          Map<String, dynamic> consent(Map<String, dynamic> shown) => {
            'action': 'approve_finances',
            'task_version': shown['version'],
            'financial_scope': shown['financial_approval_scope'],
          };
          final shown = task(papa, ids.first);
          if (mode == 'repeat_template' || mode == 'repeat_override') {
            await editTask(ids[1], 1000000);
            await refresh(papa);
            final id = mode == 'repeat_template' ? ids.first : ids[1];
            await change(
              papa,
              '/v1/tasks/$id/actions',
              consent(task(papa, id)),
            );
            expect(
              task(papa, ids.first)['financial_approved'],
              mode == 'repeat_template' ? 1 : 0,
            );
            expect(
              task(papa, ids[1])['financial_approved'],
              mode == 'repeat_override' ? 1 : 0,
            );
            expect(
              task(papa, ids[2])['financial_approved'],
              mode == 'repeat_template' ? 1 : 0,
            );
          } else if (mode == 'lost_reply' || mode == 'offline_terms') {
            final transport = papa.transport as FinancialTransport;
            if (mode == 'lost_reply') {
              transport.loseReply = true;
            } else {
              transport.offline = true;
            }
            final queued = await change(
              papa,
              '/v1/tasks/${ids.first}/actions',
              consent(shown),
            );
            expect(queued['queued'], true);
            expect(
              queued['message'],
              contains('Согласование условий ещё не подтверждено'),
            );
            await editTask(ids.first, 1000000);
            transport.offline = false;
            await refresh(papa);
            final pending = await papa.repo.pending() as List;
            expect(
              mode == 'lost_reply'
                  ? pending.isEmpty
                  : pending.single['state'] == 'failed',
              true,
            );
            expect(task(papa, ids.first)['financial_approved'], 0);
          } else {
            await editTask(ids.first, 1000000);
            final phone = mode == 'legacy_terms' ? mama : papa;
            await expectLater(
              change(
                phone,
                '/v1/tasks/${ids.first}/actions',
                mode == 'legacy_terms'
                    ? {'action': 'approve_finances'}
                    : consent(shown),
              ),
              throwsA(
                predicate(
                  (e) =>
                      e is ApiFailure && e.status == 409 ||
                      mode == 'legacy_terms' &&
                          e.toString().contains('Задание уже изменилось'),
                ),
              ),
            );
            if (mode == 'stale_terms') {
              expect(task(papa, ids.first)['reward'], 1000000);
              expect(
                task(papa, ids.first)['version'],
                greaterThan(shown['version'] as int),
              );
            }
            await refresh(papa);
            expect(task(papa, ids.first)['financial_approved'], 0);
          }
          for (final phone in [papa, mama, phones['kid']!]) {
            await refresh(phone);
            expect(phone.data['balance']['total'], 0);
            expect(phone.rows('ledger'), isEmpty);
          }
          results.add({
            'mode': mode,
            'passed': true,
            'real_isolated_https': true,
            'synthetic_family_only': true,
            'physical_phones': false,
          });
        } finally {
          for (final phone in phones.values) {
            await phone.close();
          }
          control.close();
          await deleteOwnedTestTemp(folder);
        }
      },
      skip: endpoint.isEmpty
          ? 'Requires isolated financial approval TLS fixture'
          : false,
    );
  }
  tearDownAll(() async {
    if (endpoint.isEmpty) return;
    await File(Platform.environment['MYKIDS_MIXED_REPORT']!).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'passed': results.length == modes.length,
        'cases': results,
        'physical_phones': false,
      }),
    );
  });
}
