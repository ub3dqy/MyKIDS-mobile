import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_photo_viewer.dart';
import 'package:mykids_family/updates.dart';
import 'package:path_provider/path_provider.dart';

import '../test/resume_refresh_test.dart'
    show ResumeBackground, NoResumeUpdates;

class UpgradeTransport extends http.BaseClient {
  final inner = http.Client();
  bool offline = false;
  final keys = <String>[];
  int attempted = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    attempted++;
    if (offline) {
      throw const SocketException(
        'Synthetic network unavailable during update',
      );
    }
    if (request.headers['Idempotency-Key'] case final String key) keys.add(key);
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual signed package replacement preserves family data and media',
    (tester) async {
      final directory = (await getApplicationSupportDirectory()).path;
      final config = jsonDecode(
        await File('$directory/preserve-config.json').readAsString(),
      ) as Map;
      final actor = config['actor'] as String,
          phase = config['phase'] as String;
      final report = File('$directory/preserve-$actor-$phase.json');
      final marker = File('$directory/preserve-$actor-marker.json');
      try {
        final info = (await nativeUpdates.invokeMapMethod<String, dynamic>(
          'appInfo',
        ))!;
        expect(info['package'], 'ru.mykids.mykids_family.parent');
        expect(
          info['signerSha256'],
          '2d09cc67a8bba22f5bd7ff5138347702ab767e81cce3bb87941bc9d28997db24',
        );
        expect(info['versionCode'], phase == 'prepare' ? 40 : 41);
        final transport = UpgradeTransport()..offline = phase == 'offline';
        final repo = FamilyRepository(client: transport);
        await repo.initialize();
        final ids = (config['photo_ids'] as List).cast<String>();
        if (phase == 'prepare') {
          await repo.login(
            'http://127.0.0.1:19078',
            actor,
            'synthetic-family-only-123',
          );
          final paths = <String>[], hashes = <String>[];
          for (final id in ids) {
            final file = await repo.attachment(id);
            paths.add(file.path);
            hashes.add(sha256.convert(await file.readAsBytes()).toString());
          }
          final kept = <String>[];
          if (actor == 'kid') {
            final image = await rootBundle.load('assets/generated/book-v1.png');
            final source = File('$directory/selected-page.png');
            await source.writeAsBytes(
              image.buffer.asUint8List(
                image.offsetInBytes,
                image.lengthInBytes,
              ),
            );
            for (var i = 0; i < 2; i++) {
              kept.add(await repo.keepFile(source.path));
            }
          }
          transport.offline = true;
          if (actor == 'kid') repo.online = false;
          final result = await repo.mutate(
            '/v1/tasks/${config['task_id']}/${actor == 'kid' ? 'submissions' : 'actions'}',
            actor == 'kid'
                ? {
                    'task_version': 1,
                    'marked_at': DateTime.now().toUtc().toIso8601String(),
                  }
                : {'action': 'approve'},
            files: kept,
            offlineSubmission: actor == 'kid',
          );
          expect(result['queued'], true);
          final row = (await repo.pending()).single;
          await marker.writeAsString(
            jsonEncode({
              'snapshot': repo.snapshot,
              'tag': repo.sessionTag,
              'queue': row,
              'photos': paths,
              'hashes': hashes,
              'kept': kept,
              'kept_hashes': [
                for (final path in kept)
                  sha256.convert(await File(path).readAsBytes()).toString(),
              ],
            }),
            flush: true,
          );
        } else {
          final saved = jsonDecode(await marker.readAsString()) as Map;
          expect(repo.signedIn, true);
          expect(repo.sessionTag, saved['tag']);
          expect(repo.userId, (saved['snapshot'] as Map)['user']['id']);
          if (phase == 'offline') {
            expect(repo.snapshot, saved['snapshot']);
            final row = (await repo.pending()).single;
            for (final key in [
              'id',
              'path',
              'method',
              'body',
              'files',
              'auth_tag',
              'state',
            ]) {
              expect(row[key], saved['queue'][key]);
            }
            final calls = transport.attempted;
            for (var i = 0; i < ids.length; i++) {
              final file = await repo.attachment(ids[i]);
              expect(file.path, saved['photos'][i]);
              expect(
                sha256.convert(await file.readAsBytes()).toString(),
                saved['hashes'][i],
              );
            }
            expect(transport.attempted, calls);
            final kept = (saved['kept'] as List).cast<String>();
            for (var i = 0; i < kept.length; i++) {
              expect(
                sha256.convert(await File(kept[i]).readAsBytes()).toString(),
                saved['kept_hashes'][i],
              );
            }
            await tester.pumpWidget(
              MaterialApp(
                home: TaskPhotoViewer(
                  repository: repo,
                  photos: [for (final id in ids) () => repo.attachment(id)],
                ),
              ),
            );
            Future<void> imageReady() async {
              for (var i = 0; i < 200; i++) {
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 25)),
                );
                await tester.pump();
                final images = find.byType(RawImage);
                if (images.evaluate().isNotEmpty &&
                    tester.widget<RawImage>(images.first).image != null) {
                  return;
                }
              }
              fail('Saved photo did not render after package update');
            }

            await imageReady();
            await tester.tap(find.byTooltip('Увеличить'));
            await tester.pump();
            final viewer = tester.widget<InteractiveViewer>(
              find.byKey(const ValueKey('task-photo-zoom')),
            );
            expect(
              viewer.transformationController!.value.getMaxScaleOnAxis(),
              greaterThan(1),
            );
            await tester.tap(find.byTooltip('Следующее фото'));
            await tester.pump();
            await imageReady();
            expect(transport.attempted, calls);
            await tester.pumpWidget(const SizedBox.shrink());
          } else {
            expect(phase, 'online');
            final background = ResumeBackground(repo);
            await tester.pumpWidget(
              MyKidsApp(
                repository: repo,
                createBackground: (_) => background,
                createUpdates: NoResumeUpdates.new,
                now: () => DateTime.utc(2026, 10, 16, 12),
              ),
            );
            for (
              var i = 0;
              i < 400 &&
                  !(repo.online &&
                      repo.snapshot?['balance']?['total'] == config['total']);
              i++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 50)),
              );
              await tester.pump();
            }
            expect(repo.snapshot!['balance']['total'], config['total']);
            expect(repo.online, true);
            expect(await repo.pending(), isEmpty);
            expect(
              transport.keys.where((key) => key == saved['queue']['id']),
              hasLength(1),
            );
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
                  .singleWhere((e) => e['id'] == config['event_id'])['title'],
              'После обновления',
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
              1,
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
            await tester.pumpWidget(const SizedBox.shrink());
            await repo.sync();
          }
        }
        await repo.db!.close();
        repo.client.close();
        repo.dispose();
        await report.writeAsString(
          jsonEncode({
            'ok': true,
            'actor': actor,
            'phase': phase,
            'version': info['version'],
            'version_code': info['versionCode'],
            'production_signer_verified': true,
            'photos_retained': true,
            'offline_photo_zoom_verified': phase == 'offline',
            'secure_session_retained': true,
            'queue_and_financial_counters_verified': phase == 'online',
          }),
          flush: true,
        );
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
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
