import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mixed_versions_test.dart' show HistoricalPhone, MixedTransport;

import 'support/owned_temp.dart';
import 'support/live_api_platform.dart';

class ReviewTransport extends MixedTransport {
  bool loseReviewReply = false;
  ReviewTransport(super.inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await super.send(request);
    if (loseReviewReply && request.url.path.endsWith('/actions')) {
      loseReviewReply = false;
      // The real API has committed. Lose only its acknowledgement, forcing a
      // replay of the original UUID rather than a new financial operation.
      await response.stream.drain<void>();
      throw const SocketException(
        'Synthetic acknowledgement lost after commit',
      );
    }
    return response;
  }
}

class ReviewForeground extends BackgroundServices {
  ReviewForeground(super.repository);
  @override
  Future<void> reminders() async {}
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
    'equal',
    'different',
    'zero',
    'lost_reply',
    'returned',
    'cancelled',
  ]) {
    test(
      'three live clients after competing reviews: $mode',
      () async {
        final fixture = Directory(Platform.environment['MYKIDS_MIXED_FOLDER']!);
        final context = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/ca.pem');
        http.Client client() => IOClient(HttpClient(context: context));
        final control = client();
        final folder = await Directory.systemTemp.createTemp(
          'mykids-review-clients-',
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
            Map<String, dynamic> body, {
            List<String> files = const [],
          }) async {
            phone.activate(endpoint);
            return phone.repo.mutate(path, body, files: files);
          }

          final created = await command(papa, '/v1/tasks', {
            'title': 'Одновременная проверка',
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
          final id = (created['ids'] as List).single as String;
          final files = <String>[];
          kid.activate(endpoint);
          for (var page = 0; page < 2; page++) {
            files.add(
              await kid.repo.keepFile('${fixture.path}/page$page.png')
                  as String,
            );
          }
          await command(kid, '/v1/tasks/$id/submissions', {
            'task_version': 1,
            'marked_at': DateTime.now().toUtc().toIso8601String(),
          }, files: files);
          for (final phone in phones.values) {
            await phone.repo.sync();
            expect(phone.rows('tasks').single['status'], 'submitted');
          }
          final hashes = <String, String>{};
          Future<void> photos() async {
            for (final phone in phones.values) {
              final ids = jsonDecode(
                phone.rows('submissions').single['attachment_ids'] as String,
              ) as List;
              expect(ids, hasLength(2));
              for (final photoId in ids.cast<String>()) {
                phone.activate(endpoint);
                final file = await phone.repo.attachment(photoId) as File;
                final hash = sha256
                    .convert(await file.readAsBytes())
                    .toString();
                expect(hash, hashes.putIfAbsent(photoId, () => hash));
              }
            }
          }

          await photos();
          final path = '/v1/tasks/$id/actions';
          final count = mode == 'zero' ? 4 : 5;
          Map<String, dynamic> approval(int n) => {
            'action': 'approve',
            'task_version': 1,
            'completed_count': n,
          };
          if (mode == 'lost_reply') {
            (papa.transport as ReviewTransport).loseReviewReply = true;
            final queued = await command(papa, path, approval(5));
            expect(queued['queued'], true);
            final pending = (await papa.repo.pending() as List).single as Map;
            await command(mama, path, approval(6));
            await papa.repo.sync();
            expect(await papa.repo.pending(), isEmpty);
            expect(papa.transport.commands[pending['id']], 2);
          } else if (mode == 'returned' || mode == 'cancelled') {
            // Mama still has the original submitted result open when Papa wins.
            await command(papa, path, {
              'action': mode == 'returned' ? 'return' : 'cancel',
              'note': 'Проверено',
            });
            var rejected = false;
            try {
              await command(mama, path, approval(6));
            } on ApiFailure catch (error) {
              expect(error.status, 409);
              rejected = true;
            }
            expect(rejected, true);
            // No manual sync: the competing action must refresh before throwing.
            expect(mama.rows('tasks').single['status'], mode);
            expect(mama.data['balance']['total'], 0);
          } else {
            final pending = <Future<dynamic>>[];
            for (var press = 0; press < 10; press++) {
              final phone = press.isEven ? papa : mama;
              final chosen = mode == 'equal'
                  ? 5
                  : press.isEven
                  ? count
                  : 6;
              pending.add(command(phone, path, approval(chosen)));
            }
            await Future.wait(pending);
          }
          // Deliver the real application's foreground handler. FCM transport is
          // simulated; the HTTP requests, SQLite queues and API are real.
          await Future.wait(
            services.map(
              (service) => service.handleForegroundMessage(
                RemoteMessage(data: {'kind': 'calendar', 'entity_id': id}),
              ),
            ),
          );
          final task = kid.rows('tasks').single;
          final coins = task['status'] == 'completed'
              ? task['awarded_reward'] as int
              : 0;
          if (mode == 'equal' || mode == 'lost_reply') expect(coins, 25);
          if (mode == 'different') expect(coins, isIn([25, 50]));
          if (mode == 'zero') expect(coins, isIn([0, 50]));
          for (final phone in phones.values) {
            expect(phone.rows('tasks').single, task);
            expect(phone.data['balance']['total'], coins);
            expect(phone.data['balance']['available'], coins);
            expect(
              phone.rows('tasks').where((row) => row['status'] == 'submitted'),
              isEmpty,
            );
            expect(phone.rows('ledger'), hasLength(coins > 0 ? 1 : 0));
          }
          await photos();
          results.add({
            'mode': mode,
            'status': task['status'],
            'coins': coins,
            'ledger_entries': coins > 0 ? 1 : 0,
            'unreviewed_tasks': 0,
            'three_clients_equal_without_restart': true,
            'two_photos_unchanged': true,
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
          ? 'Run verify_mixed_versions.py --suite reviews'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  tearDownAll(() async {
    if (endpoint.isEmpty) return;
    await File(Platform.environment['MYKIDS_MIXED_REPORT']!).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'utc': DateTime.now().toUtc().toIso8601String(),
        'method': 'Three real repositories and isolated HTTPS API; simulated FCM delivery; no physical phones',
        'expected': 6,
        'passed': results.length,
        'cases': results,
      }),
      flush: true,
    );
  });
}
