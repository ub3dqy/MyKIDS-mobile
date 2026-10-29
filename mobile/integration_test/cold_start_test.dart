import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:family_runtime/family_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:path_provider/path_provider.dart';

import '../test/resume_refresh_test.dart'
    show ResumeBackground, NoResumeUpdates;

class ColdTransport extends http.BaseClient {
  final inner = http.Client();
  bool offline = false;
  String? holdPath;
  final accepted = Completer<void>();
  final held = Completer<void>();
  final keys = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw const SocketException('Synthetic offline restart');
    if (request.headers['Idempotency-Key'] case final String key) keys.add(key);
    final response = await inner.send(request);
    if (request.url.path == holdPath) {
      // Consume the real API response so the server has committed. Hide only
      // its acknowledgment, then let the host kill the Android process.
      final bytes = await response.stream.toBytes();
      expect(response.statusCode, 200, reason: utf8.decode(bytes));
      accepted.complete();
      await held.future;
      return http.StreamedResponse(Stream.value(bytes), response.statusCode);
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'persistent cold start across actual Android process death and boot',
    (tester) async {
      final directory = (await getApplicationSupportDirectory()).path;
      final config = jsonDecode(
        await File('$directory/coldstart-config.json').readAsString(),
      ) as Map;
      final actor = config['actor'] as String,
          phase = config['phase'] as String;
      final report = File('$directory/coldstart-$actor-$phase.json');
      try {
        final transport = ColdTransport()..offline = phase == 'offline';
        final repo = FamilyRepository(client: transport);
        await repo.initialize();
        final marker = File('$directory/coldstart-$actor-marker.json');
        if (phase == 'prepare') {
          await repo.login(
            'http://127.0.0.1:19077',
            actor,
            'synthetic-family-only-123',
          );
          final paths = <String>[];
          if (actor == 'kid') {
            final asset = await rootBundle.load('assets/generated/book-v1.png');
            for (var i = 0; i < 2; i++) {
              final source = File('$directory/page-$i.png');
              await source.writeAsBytes(
                asset.buffer.asUint8List(
                  asset.offsetInBytes,
                  asset.lengthInBytes,
                ),
              );
              paths.add(await repo.keepFile(source.path));
            }
          }
          final path =
              '/v1/tasks/${config['task_id']}/${actor == 'kid' ? 'submissions' : 'actions'}';
          transport.holdPath = path;
          final before = repo.snapshot!;
          unawaited(
            repo.mutate(
              path,
              actor == 'kid'
                  ? {
                      'task_version': 1,
                      'marked_at': DateTime.now().toUtc().toIso8601String(),
                    }
                  : {'action': 'approve'},
              offlineSubmission: actor == 'kid',
              files: paths,
            ),
          );
          await transport.accepted.future;
          final row = (await repo.pending()).single;
          expect(row['lease_owner'], await familyProcessIdentity());
          expect(
            row['lease_until'] as int,
            greaterThan(DateTime.now().millisecondsSinceEpoch),
          );
          final saved = {
            'actor': actor,
            'snapshot': before,
            'session_tag': repo.sessionTag,
            'command_id': row['id'],
            'command_body': row['body'],
            'paths': paths,
            'hashes': [
              for (final path in paths)
                sha256.convert(await File(path).readAsBytes()).toString(),
            ],
            'process': await familyProcessIdentity(),
            'pid': pid,
          };
          await marker.writeAsString(jsonEncode(saved), flush: true);
          await report.writeAsString(
            jsonEncode({
              'ok': true,
              'phase': phase,
              'actor': actor,
              'server_committed_ack_held': true,
              'lease_active': true,
              'pid': pid,
              'process': saved['process'],
            }),
            flush: true,
          );
          // The host terminates this process while the command is awaiting ACK.
          await transport.held.future;
          fail('The host must actually kill this process');
        }
        final saved = jsonDecode(await marker.readAsString()) as Map;
        expect(repo.signedIn, true);
        expect(repo.userId, (saved['snapshot'] as Map)['user']['id']);
        expect(repo.sessionTag, saved['session_tag']);
        expect(await familyProcessIdentity(), isNot(saved['process']));
        final pending = await repo.pending();
        if (phase == 'offline' || phase == 'online') {
          expect(repo.snapshot, saved['snapshot']);
          expect(pending.single['id'], saved['command_id']);
          expect(pending.single['body'], saved['command_body']);
          final paths = (saved['paths'] as List).cast<String>();
          for (var i = 0; i < paths.length; i++) {
            expect(
              sha256.convert(await File(paths[i]).readAsBytes()).toString(),
              saved['hashes'][i],
            );
          }
        } else {
          expect(phase, 'final');
          expect(pending, isEmpty);
          expect(repo.snapshot, saved['fresh_snapshot']);
        }
        // Hold background initialization to also exercise independent cold sync.
        final background = ResumeBackground(repo)
          ..initialization = Completer<void>();
        await tester.pumpWidget(
          MyKidsApp(
            repository: repo,
            createBackground: (_) => background,
            createUpdates: NoResumeUpdates.new,
            now: () => DateTime.utc(2026, 10, 16, 12),
          ),
        );
        Future<void> until(bool Function() ready) async {
          for (var i = 0; i < 400 && !ready(); i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump();
          }
          expect(ready(), true);
        }

        if (phase == 'offline') {
          await until(() => !repo.syncing);
          expect(repo.online, false);
          expect(repo.snapshot, saved['snapshot']);
          expect((await repo.pending()).single['id'], saved['command_id']);
          expect(await repo.storage.read(key: 'session'), isNotNull);
        } else {
          await until(
            () =>
                repo.online &&
                repo.snapshot?['balance']?['total'] == config['total'],
          );
          expect(await repo.pending(), isEmpty);
          expect(
            repo
                .rows('tasks')
                .singleWhere((t) => t['id'] == config['task_id'])['status'],
            config['status'],
          );
          expect(
            repo
                .rows('rewards')
                .singleWhere((r) => r['id'] == config['reward_id'])['price'],
            60,
          );
          expect(
            repo
                .rows('schedules')
                .singleWhere((s) => s['id'] == config['event_id'])['title'],
            'После перезагрузки',
          );
          expect(
            repo.rows('grades').any((g) => g['id'] == config['grade_id']),
            true,
          );
          expect(
            repo
                .rows('rooms')
                .singleWhere(
                  (r) => r['id'] == config['room_id'],
                )['unread_count'],
            phase == 'final' ? 0 : 1,
          );
          if (phase == 'online') {
            expect(
              transport.keys.where((key) => key == saved['command_id']),
              hasLength(1),
            );
            await repo.mutate('/v1/messages/${config['message_id']}/receipt', {
              'status': 'read',
            });
            expect(
              repo
                  .rows('rooms')
                  .singleWhere(
                    (r) => r['id'] == config['room_id'],
                  )['unread_count'],
              0,
            );
          }
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            if (find.text('Здорово!').evaluate().isNotEmpty) {
              await tester.tap(find.text('Здорово!'));
            }
          }
          await tester.pumpAndSettle();
          await tester.tap(find.text('Монеты').last);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Всего: ${config['total']}'),
            findsOneWidget,
          );
        }
        // Stop UI polling, then persist one final snapshot. No in-flight poll
        // may update volatile server timestamps after the saved checkpoint.
        await tester.pumpWidget(const SizedBox.shrink());
        background.initialization!.complete();
        await tester.pump();
        await repo.sync();
        if (phase != 'offline') {
          saved['fresh_snapshot'] = repo.snapshot;
          await marker.writeAsString(jsonEncode(saved), flush: true);
        }
        await report.writeAsString(
          jsonEncode({
            'ok': true,
            'actor': actor,
            'phase': phase,
            'session_retained': true,
            'cached_data_retained': true,
            'pid': pid,
            'process': await familyProcessIdentity(),
            'pending': (await repo.pending()).length,
            'online': repo.online,
            'balance': repo.snapshot?['balance'],
            'read_count_persisted': phase == 'final',
            'child_photo_files_verified': actor == 'kid' && phase != 'final',
            'first_sync_before_notifications_ready': phase != 'offline',
          }),
          flush: true,
        );
        await repo.db!.close();
        repo.client.close();
        repo.dispose();
      } catch (error, stack) {
        await report.writeAsString(
          jsonEncode({
            'ok': false,
            'actor': actor,
            'phase': phase,
            'error': error.toString(),
            'stack': stack.toString(),
          }),
          flush: true,
        );
        rethrow;
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
