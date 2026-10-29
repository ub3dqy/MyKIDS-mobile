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

class GradeTransport extends MixedTransport {
  bool loseGradeReply = false;
  final gradeKeys = <String>[];
  GradeTransport(super.inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final grade =
        request.method != 'GET' &&
        (request.url.path == '/v1/grades' ||
            request.url.path.startsWith('/v1/grades/'));
    if (grade) gradeKeys.add(request.headers['Idempotency-Key']!);
    final response = await super.send(request);
    if (grade && loseGradeReply) {
      loseGradeReply = false;
      await response.stream.drain<void>();
      throw const SocketException(
        'Synthetic grade acknowledgement lost after commit',
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
    'create_positive',
    'create_penalty',
    'create_different',
    'edit_equal',
    'edit_different',
    'edit_penalty',
    'edit_after_debit',
    'metadata',
    'lost_create',
    'lost_edit',
    'replay_after_edit',
    'grade_vs_penalty',
  ]) {
    test(
      'one grade and three clients: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-grade-clients-',
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
          for (final actor in ['kid', 'papa', 'mama']) {
            final directory = await Directory('${folder.path}/$actor').create();
            final phone = HistoricalPhone(
              actor,
              'current',
              directory,
              GradeTransport(client()),
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

          Future<int> attempt(
            HistoricalPhone phone,
            String path,
            Map<String, dynamic> body, {
            String method = 'POST',
          }) async {
            try {
              await command(phone, path, body, method: method);
              return 200;
            } on ApiFailure catch (error) {
              return error.status;
            }
          }

          await command(papa, '/v1/grade-rules', {
            'amounts': {'5': 25, '4': 10, '3': 0, '2': -40},
          }, method: 'PUT');
          final schedule = await command(papa, '/v1/schedules', {
            'title': 'Школа',
            'kind': 'school',
            'date': '2030-09-02',
            'start': '09:00',
            'end': '14:00',
            'activities': [
              {'title': 'Математика', 'start': '09:00', 'end': '10:00'},
            ],
          });
          final activity = (jsonDecode(
            papa.rows('schedules').single['activities'] as String,
          ) as List).single;
          final source = <String, dynamic>{
            'schedule_id': schedule['id'],
            'activity_id': activity['id'],
            'date': '2030-09-02',
          };
          final create = mode.startsWith('create_') || mode == 'lost_create';
          var id = '';
          if (!create) {
            final initial =
                ['edit_after_debit', 'grade_vs_penalty'].contains(mode)
                ? 2
                : [
                    'edit_penalty',
                    'metadata',
                    'replay_after_edit',
                  ].contains(mode)
                ? 5
                : 3;
            final response = await command(papa, '/v1/grades', {
              ...source,
              'grade': initial,
            });
            id = response['id'] as String;
            if (mode == 'edit_after_debit') {
              final penalty = papa.rows('penalties').single['id'];
              await command(mama, '/v1/penalties/$penalty/approve', {});
            }
          }
          for (final phone in phones.values) {
            await phone.repo.sync();
          }
          final changesBefore = {
            for (final phone in phones.values) phone.actor: phone.changes,
          };
          final opened = create
              ? null
              : Map<String, dynamic>.from(papa.rows('grades').single);
          Map<String, dynamic> edit(int value, {String? note}) => {
            ...source,
            'grade': value,
            'expected_revision': opened!['revision'],
            'note': ?note,
          };
          final path = create ? '/v1/grades' : '/v1/grades/$id';
          if (mode.startsWith('create_')) {
            final replies = await Future.wait([
              for (var i = 0; i < 8; i++)
                attempt(i.isEven ? papa : mama, path, {
                  ...source,
                  'grade': mode == 'create_penalty'
                      ? 2
                      : mode == 'create_different' && i.isOdd
                      ? 4
                      : 5,
                }),
            ]);
            expect(replies.where((r) => r == 200), hasLength(1));
            expect(replies.where((r) => r == 409), hasLength(7));
            expect(papa.rows('grades'), hasLength(1));
            expect(mama.rows('grades'), hasLength(1));
            expect(
              papa.data['balance']['total'],
              mama.data['balance']['total'],
            );
          } else if (mode == 'lost_create' || mode == 'lost_edit') {
            (papa.transport as GradeTransport).loseGradeReply = true;
            final reply = await command(
              papa,
              path,
              create ? {...source, 'grade': 5} : edit(5),
              method: create ? 'POST' : 'PUT',
            );
            expect(reply['queued'], true);
            final pending = (await papa.repo.pending() as List).single as Map;
            await papa.repo.sync();
            expect(papa.transport.commands[pending['id']], 2);
            expect(await papa.repo.pending(), isEmpty);
          } else if (mode == 'replay_after_edit') {
            final response = await command(papa, path, edit(4), method: 'PUT');
            expect(response['id'], id);
            final key = (papa.transport as GradeTransport).gradeKeys.last;
            final current = mama.repo as FamilyRepository;
            await current.sync();
            await command(mama, path, {
              ...source,
              'grade': 3,
              'expected_revision': mama.rows('grades').single['revision'],
            }, method: 'PUT');
            await papa.repo.db.insert('outbox', <String, Object?>{
              'id': key,
              'path': path,
              'method': 'PUT',
              'body': papa.transport.bodies[key],
              'files': '[]',
              'state': 'pending',
              'auth_tag': papa.repo.sessionTag,
            });
            await papa.repo.sync();
            expect(papa.transport.commands[key], 2);
            expect(papa.rows('grades').single['grade'], 3);
            expect(await attempt(papa, path, edit(4), method: 'PUT'), 409);
            expect(papa.rows('grades').single['grade'], 3);
          } else if (mode == 'grade_vs_penalty') {
            final penalty = papa.rows('penalties').single['id'];
            await Future.wait([
              command(papa, path, edit(5), method: 'PUT'),
              command(mama, '/v1/penalties/$penalty/approve', {}),
            ]);
          } else {
            final replies = await Future.wait([
              for (var i = 0; i < 8; i++)
                attempt(
                  i.isEven ? papa : mama,
                  path,
                  mode == 'metadata'
                      ? edit(5, note: i.isEven ? 'Папа' : 'Мама')
                      : edit(
                          mode == 'edit_penalty'
                              ? 2
                              : mode == 'edit_different' && i.isOdd
                              ? 4
                              : 5,
                        ),
                  method: 'PUT',
                ),
            ]);
            expect(replies.where((r) => r == 200), hasLength(1));
            expect(replies.where((r) => r == 409), hasLength(7));
            expect(papa.rows('grades').single, mama.rows('grades').single);
            expect(
              papa.data['balance']['total'],
              mama.data['balance']['total'],
            );
          }
          id = papa.rows('grades').single['id'] as String;
          Future<void> notify() => Future.wait(
            services.map(
              (service) => service.handleForegroundMessage(
                RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
              ),
            ),
          );
          await notify();
          id = kid.rows('grades').single['id'] as String;
          final pending = kid
              .rows('penalties')
              .where((p) => p['status'] == 'pending')
              .toList();
          if (pending.isNotEmpty) {
            expect(pending, hasLength(1));
            await Future.wait([
              for (var i = 0; i < 8; i++)
                command(
                  i.isEven ? papa : mama,
                  '/v1/penalties/${pending.single['id']}/approve',
                  {},
                ),
            ]);
            await notify();
          }
          final grade = kid.rows('grades').single;
          final amount = {5: 25, 4: 10, 3: 0, 2: -40}[grade['grade']]!;
          for (final phone in phones.values) {
            expect(phone.rows('grades'), [grade]);
            expect(phone.data['balance']['total'], amount);
            expect(phone.data['balance']['available'], amount);
            expect(phone.data['balance']['reserved'], 0);
            expect(
              phone.rows('penalties').where((p) => p['status'] == 'pending'),
              isEmpty,
            );
            final ledger = phone
                .rows('ledger')
                .where((e) => e['source_id'] == id)
                .toList();
            expect(
              ledger.fold<int>(0, (sum, e) => sum + (e['actual'] as int)),
              amount,
            );
            expect(
              ledger.map((e) => e['event_key']).toSet(),
              hasLength(ledger.length),
            );
            expect(phone.changes, greaterThan(changesBefore[phone.actor]!));
          }
          results.add({
            'mode': mode,
            'grade': grade['grade'],
            'coins': amount,
            'money_entries': kid.rows('ledger').length,
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
          ? 'Run verify_mixed_versions.py --suite grades'
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
        'expected': 12,
        'passed': results.length,
        'cases': results,
      }),
      flush: true,
    );
  });
}
