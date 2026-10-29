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

class PermissionTransport extends MixedTransport {
  bool loseReply = false;
  PermissionTransport(super.inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await super.send(request);
    if (loseReply &&
        request.method == 'PATCH' &&
        request.url.path.startsWith('/v1/members/')) {
      loseReply = false;
      await response.stream.drain<void>();
      throw const SocketException(
        'Synthetic permission reply lost after the actual commit',
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
    'one_permission',
    'stale_after_revoke',
    'simultaneous_parents',
    'lost_reply_then_revoke',
    'offline_then_revoke',
    'legacy_stale_flags',
  ]) {
    test(
      'family access with four actual TLS clients: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-permission-clients-',
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
              'current',
              await Directory('${folder.path}/$actor').create(),
              PermissionTransport(client()),
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
          Map<String, dynamic> member(HistoricalPhone phone) => phone
              .rows('members')
              .singleWhere((row) => row['role'] == 'relative');
          Future<void> refresh(HistoricalPhone phone) async {
            phone.activate(endpoint);
            await phone.repo.sync();
          }

          final id = member(papa)['id'], path = '/v1/members/$id';
          Future<Map<String, dynamic>> change(
            HistoricalPhone phone,
            Map<String, dynamic> flags, {
            String? revision,
            bool legacy = false,
          }) async {
            phone.activate(endpoint);
            return Map<String, dynamic>.from(
              await phone.repo.mutate(path, {
                ...flags,
                if (!legacy)
                  'expected_revision':
                      revision ?? member(phone)['permissions_revision'],
              }, method: 'PATCH'),
            );
          }

          await change(papa, {
            'create_tasks': true,
            'view_tasks': true,
            'review_tasks': true,
          });
          await refresh(mama);
          final original = Map<String, dynamic>.from(member(papa));
          if (mode == 'one_permission') {
            await change(papa, {'view_tasks': false});
            expect(member(papa)['create_tasks'], 1);
            expect(member(papa)['review_tasks'], 1);
            expect(member(papa)['active'], 1);
            expect(member(papa)['view_tasks'], 0);
          } else if (mode == 'simultaneous_parents') {
            Future<int> attempt(HistoricalPhone phone, String flag) async {
              try {
                await change(phone, {flag: false});
                return 200;
              } on ApiFailure catch (failure) {
                return failure.status;
              }
            }

            final outcomes = await Future.wait([
              attempt(papa, 'view_tasks'),
              attempt(mama, 'review_tasks'),
            ]);
            expect(outcomes.toList()..sort(), [200, 409]);
            await refresh(papa);
            expect(member(papa)['active'], 1);
            expect(member(papa)['create_tasks'], 1);
            expect([
              member(papa)['view_tasks'],
              member(papa)['review_tasks'],
            ], outcomes.first == 200 ? [0, 1] : [1, 0]);
          } else {
            final transport = papa.transport as PermissionTransport;
            if (mode == 'lost_reply_then_revoke' ||
                mode == 'offline_then_revoke') {
              transport.loseReply = mode == 'lost_reply_then_revoke';
              transport.offline = mode == 'offline_then_revoke';
              final queued = await change(papa, {'view_tasks': false});
              expect(queued['queued'], true);
              expect(queued['message'], contains('ещё не подтверждено'));
              expect(
                (await papa.repo.pending() as List).single['state'],
                'pending',
              );
              // The second parent sees the actual committed state before revoking.
              await refresh(mama);
            }
            await change(mama, {'active': false});
            if (mode == 'stale_after_revoke' || mode == 'legacy_stale_flags') {
              await expectLater(
                change(
                  papa,
                  mode == 'legacy_stale_flags'
                      ? {
                          'create_tasks': true,
                          'view_tasks': false,
                          'review_tasks': true,
                          'active': true,
                        }
                      : {'view_tasks': false},
                  revision: original['permissions_revision'] as String,
                  legacy: mode == 'legacy_stale_flags',
                ),
                throwsA(
                  isA<ApiFailure>().having((e) => e.status, 'status', 409),
                ),
              );
              // The conflict updates the visible state before surfacing the error.
              expect(member(papa)['active'], 0);
            } else {
              transport.offline = false;
              await refresh(papa);
              final pending = await papa.repo.pending() as List;
              if (mode == 'lost_reply_then_revoke') {
                expect(pending, isEmpty);
                expect(
                  transport.commands.values.where((n) => n == 2),
                  hasLength(1),
                );
              } else {
                expect(pending.single['state'], 'failed');
              }
            }
            expect(member(papa)['active'], 0);
            expect(member(papa)['create_tasks'], 1);
            expect(member(papa)['review_tasks'], 1);
            grandma.activate(endpoint);
            await grandma.repo.sync();
            expect(grandma.repo.signedIn, false);
            expect(await grandma.repo.db.query('cache'), isEmpty);
            expect(await grandma.repo.db.query('outbox'), isEmpty);
          }
          results.add({
            'mode': mode,
            'passed': true,
            'active': member(papa)['active'],
            'create_tasks': member(papa)['create_tasks'],
            'view_tasks': member(papa)['view_tasks'],
            'review_tasks': member(papa)['review_tasks'],
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
          ? 'Requires the isolated permissions TLS fixture'
          : false,
    );
  }
  tearDownAll(() async {
    if (endpoint.isEmpty) return;
    await File(Platform.environment['MYKIDS_MIXED_REPORT']!).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'passed': results.length == 6,
        'cases': results,
        'physical_phones': false,
      }),
    );
  });
}
