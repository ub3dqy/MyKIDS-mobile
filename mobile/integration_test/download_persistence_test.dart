import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/updates.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment(
    'DOWNLOAD_TEST_PHASE',
    defaultValue: 'start',
  );
  testWidgets(
    'system transfer persists across lock and process restart: $phase',
    (tester) async {
      final info = (await nativeUpdates.invokeMapMethod<String, dynamic>(
        'appInfo',
      ))!;
      expect(info['package'], 'ru.mykids.mykids_family.parent');
      expect(info['versionCode'], 12);
      final client = http.Client();
      final response = await client.get(
        Uri.parse('https://api.xn--80ajzgig.online/downloads/latest.json'),
      );
      client.close();
      expect(response.statusCode, 200);
      final entry = ((jsonDecode(response.body) as Map)['apps'] as List)
          .cast<Map>()
          .singleWhere((app) => app['role'] == 'family');
      final args = <String, Object>{
        'fileName': entry['file'] as String,
        'versionCode': entry['version_code'] as int,
        'bytes': entry['bytes'] as int,
        'sha256': entry['sha256'] as String,
        'url': entry['url'] as String,
      };
      final marker = File(
        '${info['updateDirectory']}/download-persistence-test.json',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Проверка обновления MyKIDS')),
        ),
      );
      await tester.pump();

      Future<void> checkpoint(String name) async {
        final acknowledgment = File(
          '${info['updateDirectory']}/checkpoint-$name.done',
        );
        if (await acknowledgment.exists()) await acknowledgment.delete();
        await File('${info['updateDirectory']}/host-checkpoint.request')
            .writeAsString(name);
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!await acknowledgment.exists() &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          await acknowledgment.exists(),
          true,
          reason: 'Host action did not finish',
        );
        await acknowledgment.delete();
      }

      Future<Map<String, dynamic>> status() async => (await nativeUpdates
          .invokeMapMethod<String, dynamic>('downloadStatus', args))!;

      if (phase == 'start') {
        await checkpoint('prepare-download');
        await nativeUpdates.invokeMethod<void>('cancelDownload', args);
        final started = (await nativeUpdates.invokeMapMethod<String, dynamic>(
          'startDownload',
          args,
        ))!;
        expect(started['id'], isA<int>());
        final duplicate = (await nativeUpdates.invokeMapMethod<String, dynamic>(
          'startDownload',
          args,
        ))!;
        expect(duplicate['id'], started['id']);
        var before = await status();
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while ((before['received'] as int? ?? 0) == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          before = await status();
        }
        expect(before['state'], 'running');
        expect(before['received'], greaterThan(0));
        await checkpoint('lock-download');
        final after = await status();
        expect(after['id'], started['id']);
        expect(after['received'], greaterThan(before['received'] as int));
        expect(after['state'], anyOf('running', 'ready'));
        await marker.writeAsString(jsonEncode(after));
        binding.reportData = {
          'phase': phase,
          'same_id_after_lock': true,
          'progress_during_lock': true,
          'duplicate_start_reused': true,
          'download': after,
        };
      } else {
        expect(phase, 'resume');
        final saved = jsonDecode(await marker.readAsString()) as Map;
        final restored = await status();
        expect(restored['id'], saved['id']);
        expect(
          restored['received'],
          greaterThanOrEqualTo(saved['received'] as int),
        );
        final rejoined = (await nativeUpdates.invokeMapMethod<String, dynamic>(
          'startDownload',
          args,
        ))!;
        expect(rejoined['id'], saved['id']);
        await checkpoint('finish-download');
        var completed = await status();
        final deadline = DateTime.now().add(const Duration(seconds: 180));
        while (completed['state'] != 'ready' &&
            DateTime.now().isBefore(deadline)) {
          expect(completed['state'], anyOf('running', 'paused'));
          await Future<void>.delayed(const Duration(seconds: 1));
          completed = await status();
        }
        expect(completed['state'], 'ready');
        expect(completed['id'], saved['id']);
        final downloaded = File(
          '${info['updateDirectory']}/${args['fileName']}',
        );
        expect(
          (await sha256.bind(downloaded.openRead()).first).toString(),
          args['sha256'],
        );
        final future = File('${info['updateDirectory']}/MyKIDS-0.1.12.apk');
        final verify = {
          'fileName': 'MyKIDS-0.1.12.apk',
          'versionCode': 13,
          'bytes': await future.length(),
          'sha256': (await sha256.bind(future.openRead()).first).toString(),
        };
        expect(
          await nativeUpdates.invokeMethod<String>('verifyUpdate', verify),
          'verified',
        );
        for (final invalid in [
          {...verify, 'sha256': List.filled(64, '0').join()},
          {...verify, 'versionCode': 12},
          {...verify, 'fileName': '../MyKIDS-0.1.12.apk'},
          {...verify, 'fileName': 'MyKIDS-child-0.1.12.apk'},
          args, // The downloaded public release is older than this test application.
        ]) {
          await expectLater(
            nativeUpdates.invokeMethod<String>('verifyUpdate', invalid),
            throwsA(isA<PlatformException>()),
          );
        }
        final reused = (await nativeUpdates.invokeMapMethod<String, dynamic>(
          'startDownload',
          args,
        ))!;
        expect(reused['id'], saved['id']);
        expect(reused['state'], 'ready');
        binding.reportData = {
          'phase': phase,
          'same_id_after_process_restart': true,
          'completed_sha256_verified': true,
          'completed_file_reused': true,
          'newer_signature_verified': true,
          'invalid_candidates_rejected': true,
          'download': completed,
          'scope': 'owned Android 16 emulator; no physical phone; installer confirmation not automated',
        };
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
