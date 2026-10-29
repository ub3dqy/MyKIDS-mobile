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

class TaskChangeTransport extends MixedTransport {
  bool loseReply = false;
  TaskChangeTransport(super.inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final writing =
        request.method != 'GET' && request.url.path.startsWith('/v1/tasks/');
    final response = await super.send(request);
    if (writing && loseReply) {
      loseReply = false;
      await response.stream.drain<void>();
      throw const SocketException('Synthetic committed task reply lost');
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
    'edit_cancel',
    'cancel_cancel',
    'edit_plan',
    'edit_reschedule',
    'lost_edit',
    'lost_cancel',
    'lost_plan',
    'lost_reschedule',
    'cancel_pending_penalty',
  ];
  for (final mode in modes) {
    test(
      'task changes on three live clients: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-task-change-clients-',
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
              TaskChangeTransport(client()),
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

          await command(papa, '/v1/tasks', {
            'title': 'Семейная задача',
            'description': 'Две страницы',
            'reward': 50,
            'due_at': mode == 'cancel_pending_penalty'
                ? '2020-01-01T20:00:00Z'
                : '2030-01-01T20:00:00Z',
            'is_required': mode == 'cancel_pending_penalty',
            'penalty': mode == 'cancel_pending_penalty' ? 40 : 0,
          });
          for (final phone in phones.values) {
            await phone.repo.sync();
          }
          final opened = Map<String, dynamic>.from(papa.rows('tasks').single);
          final id = opened['id'] as String, path = '/v1/tasks/${opened['id']}';
          final beforeChanges = {
            for (final phone in phones.values) phone.actor: phone.changes,
          };
          Map<String, dynamic> edit(String actor) => {
            for (final key in [
              'title',
              'description',
              'due_at',
              'reward',
              'penalty',
              'reviewer_id',
              'program_id',
              'subject_id',
              'planned_start',
              'planned_end',
              'reminder_minutes',
            ])
              key: opened[key],
            'title': 'Изменено $actor',
            'is_required': opened['is_required'] == 1,
            'require_photo': opened['require_photo'] == 1,
            'task_version': opened['version'],
          };
          Future<int> change(HistoricalPhone phone, String op) async {
            try {
              final payload = op == 'edit'
                  ? edit(phone.actor)
                  : <String, dynamic>{
                      'task_version': opened['version'],
                      if (op != 'plan') 'action': op,
                      if (op == 'reschedule') 'due_at': '2030-01-02T20:00:00Z',
                      if (op == 'plan') 'reminder_minutes': 5,
                    };
              final reply = await command(
                phone,
                op == 'edit'
                    ? path
                    : '$path/${op == 'plan' ? 'plan' : 'actions'}',
                payload,
                method: op == 'edit'
                    ? 'PUT'
                    : op == 'plan'
                    ? 'PATCH'
                    : 'POST',
              );
              return reply['queued'] == true ? 202 : 200;
            } on ApiFailure catch (error) {
              return error.status;
            }
          }

          if (mode.startsWith('lost_')) {
            (papa.transport as TaskChangeTransport).loseReply = true;
            expect(await change(papa, mode.substring(5)), 202);
            final pending = (await papa.repo.pending() as List).single as Map;
            await papa.repo.sync();
            expect(papa.transport.commands[pending['id']], 2);
            expect(await papa.repo.pending(), isEmpty);
          } else if (mode == 'cancel_pending_penalty') {
            expect(
              kid.rows('penalties').where((p) => p['status'] == 'pending'),
              hasLength(1),
            );
            expect(await change(mama, 'cancel'), 200);
          } else {
            final pair = mode.split('_');
            final replies = await Future.wait([
              for (var i = 0; i < 8; i++)
                change(i.isEven ? papa : mama, pair[i % 2]),
            ]);
            expect(replies.where((r) => r == 200), hasLength(1));
            expect(replies.where((r) => r == 409), hasLength(7));
            // Losing parents refresh as part of the failed command, before push.
            expect(papa.rows('tasks'), mama.rows('tasks'));
          }
          await Future.wait(
            services.map(
              (service) => service.handleForegroundMessage(
                RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
              ),
            ),
          );
          final winner = kid.rows('tasks').single;
          expect(winner['version'], 2);
          for (final phone in phones.values) {
            expect(phone.rows('tasks'), [winner]);
            expect(phone.data['balance']['total'], 0);
            expect(phone.data['balance']['available'], 0);
            expect(phone.rows('ledger'), isEmpty);
            expect(
              phone.rows('penalties').where((p) => p['status'] == 'pending'),
              isEmpty,
            );
            expect(phone.changes, greaterThan(beforeChanges[phone.actor]!));
          }
          if (winner['status'] != 'cancelled') {
            // Award the edited task once; duplicate reviews must retain 50 coins.
            await command(kid, '$path/submissions', {
              'task_version': winner['version'],
              'marked_at': DateTime.now().toUtc().toIso8601String(),
            });
            await Future.wait([
              for (var i = 0; i < 8; i++)
                command(i.isEven ? papa : mama, '$path/actions', {
                  'action': 'approve',
                  'task_version': winner['version'],
                }),
            ]);
            await Future.wait(
              services.map(
                (service) => service.handleForegroundMessage(
                  RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
                ),
              ),
            );
            for (final phone in phones.values) {
              expect(phone.data['balance']['total'], 50);
              expect(phone.rows('ledger'), hasLength(1));
              expect(phone.rows('tasks').single['status'], 'completed');
            }
          }
          results.add({
            'mode': mode,
            'three_clients_equal_without_restart': true,
            'coins': kid.data['balance']['total'],
            'task_version': winner['version'],
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
          ? 'Run verify_mixed_versions.py --suite task-changes'
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
        'method': 'Three actual repositories, isolated HTTPS API and SQLite; simulated FCM; no physical phones',
        'cases': results,
      }),
    );
  });
}
