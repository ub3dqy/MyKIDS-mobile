import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mixed_versions_test.dart' show HistoricalPhone, MixedTransport;
import 'review_concurrency_sync_test.dart' show ReviewForeground;

import 'support/owned_temp.dart';
import 'support/live_api_platform.dart';

class CalendarTransport extends MixedTransport {
  bool loseReply = false;
  CalendarTransport(super.inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final writing =
        request.method != 'GET' &&
        request.url.path.startsWith('/v1/schedules/');
    final response = await super.send(request);
    if (writing && loseReply) {
      loseReply = false;
      await response.stream.drain<void>();
      throw const SocketException('Synthetic committed calendar reply lost');
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
    'edit_archive',
    'replace_cancel',
    'archive_archive',
    'cancel_cancel',
    'lost_edit',
    'lost_replace',
    'lost_cancel',
    'lost_archive',
  ];
  for (final mode in modes) {
    test(
      'calendar changes on three live clients: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-calendar-clients-',
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
              CalendarTransport(client()),
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

          Map<String, dynamic> event(String title) => {
            'title': title,
            'weekdays': [1],
            'start': '12:00',
            'end': '13:00',
            'kind': 'other',
            'starts_on': '2030-09-01',
            'until': '2030-10-31',
          };
          final created = await command(
            papa,
            '/v1/schedules',
            event('Семейное событие'),
          );
          final id = created['id'] as String,
              path = '/v1/schedules/${created['id']}';
          for (final phone in phones.values) {
            await phone.repo.sync();
          }
          final revision = papa.rows('schedules').single['revision'];
          final beforeChanges = {
            for (final phone in phones.values) phone.actor: phone.changes,
          };
          Future<int> change(HistoricalPhone phone, String op) async {
            final guard = {'expected_revision': revision};
            final body = op == 'edit'
                ? {...event('Изменено ${phone.actor}'), ...guard}
                : op == 'archive'
                ? guard
                : {
                    'date': '2030-09-02',
                    ...guard,
                    if (op == 'replace')
                      'replacement': {
                        'title': 'Замена ${phone.actor}',
                        'date': '2030-09-02',
                        'start': '15:00',
                        'end': '16:00',
                        'kind': 'other',
                      },
                  };
            try {
              final reply = await command(
                phone,
                op == 'edit' || op == 'archive' ? path : '$path/exceptions',
                body,
                method: op == 'edit'
                    ? 'PUT'
                    : op == 'archive'
                    ? 'DELETE'
                    : 'POST',
              );
              return reply['queued'] == true ? 202 : 200;
            } on ApiFailure catch (error) {
              return error.status;
            }
          }

          if (mode.startsWith('lost_')) {
            (papa.transport as CalendarTransport).loseReply = true;
            expect(await change(papa, mode.substring(5)), 202);
            final pending = (await papa.repo.pending() as List).single as Map;
            await papa.repo.sync();
            expect(papa.transport.commands[pending['id']], 2);
            expect(await papa.repo.pending(), isEmpty);
          } else {
            final pair = mode.split('_');
            final replies = await Future.wait([
              for (var i = 0; i < 8; i++)
                change(i.isEven ? papa : mama, pair[i % 2]),
            ]);
            expect(replies.where((r) => r == 200), hasLength(1));
            expect(replies.where((r) => r == 409), hasLength(7));
            expect(papa.rows('schedules'), mama.rows('schedules'));
            expect(
              papa.rows('schedule_exceptions'),
              mama.rows('schedule_exceptions'),
            );
          }
          await Future.wait(
            services.map(
              (service) => service.handleForegroundMessage(
                RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
              ),
            ),
          );
          final day = DateTime.utc(2030, 9, 2, 12);
          final entries = calendarDay(kid.data, day);
          expect(entries.length, isIn([0, 1]));
          for (final phone in phones.values) {
            expect(phone.rows('schedules'), kid.rows('schedules'));
            expect(
              phone.rows('schedule_exceptions'),
              kid.rows('schedule_exceptions'),
            );
            final actual = calendarDay(phone.data, day);
            expect(
              actual.map((e) => '${e.title}|${e.timeText}'),
              entries.map((e) => '${e.title}|${e.timeText}'),
            );
            expect(actual.length, entries.length);
            expect(phone.data['balance']['total'], 0);
            expect(phone.rows('ledger'), isEmpty);
            expect(phone.changes, greaterThan(beforeChanges[phone.actor]!));
          }
          if (kid.rows('schedules').isNotEmpty) {
            expect(kid.rows('schedules').single['revision'], isNot(revision));
          }
          results.add({
            'mode': mode,
            'three_clients_equal_without_restart': true,
            'calendar_entries': entries.length,
            'coins_unchanged': true,
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
          ? 'Run verify_mixed_versions.py --suite calendars'
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
