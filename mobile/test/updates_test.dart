import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/updates.dart';

import 'support/owned_temp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  final bytes = utf8.encode(
    'synthetic updater payload, not an installable APK',
  );
  final certificate = List.filled(64, 'a').join();
  final calls = <MethodCall>[];
  Map<String, dynamic> entry({int code = 3}) => {
    'role': 'family',
    'package': 'ru.mykids.mykids_family.parent',
    'version': '0.1.2',
    'version_code': code,
    'bytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'certificate_sha256': certificate,
    'notes': 'Проверочное обновление',
    'url': 'https://family.example/downloads/MyKIDS-0.1.2.apk',
  };
  final manifestUrl = Uri.parse('https://family.example/downloads/latest.json');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('mykids-update-test-');
    calls.clear();
    messenger.setMockMethodCallHandler(nativeUpdates, (call) async {
      calls.add(call);
      if (call.method == 'appInfo') {
        return {
          'package': 'ru.mykids.mykids_family.parent',
          'versionCode': 2,
          'signerSha256': certificate,
          'updateDirectory': folder.path,
        };
      }
      return call.method == 'installUpdate' ? 'installer_opened' : null;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(nativeUpdates, null);
    expect(folder.absolute.parent.path, Directory.systemTemp.absolute.path);
    expect(
      folder.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('mykids-update-test-'),
      true,
    );
    await deleteOwnedTestTemp(folder);
  });
  AppUpdates service(List<Map<String, dynamic>> entries) => AppUpdates(
    client: MockClient((request) async {
      expect(request.headers.containsKey('Authorization'), false);
      expect(request.followRedirects, false);
      return http.Response.bytes(
        utf8.encode(jsonEncode({'schema': 1, 'apps': entries})),
        200,
      );
    }),
  );

  for (final role in ['child', 'parent', 'relative']) {
    test('same family APK for every setup role: $role', () async {
      final updater = service([entry()]);
      final offer = await updater.check(manifestUrl, role);
      expect(offer!.role, 'family');
      expect(offer.versionCode, 3);
      updater.dispose();
    });
  }
  test('same and older versions do not produce an update', () async {
    for (final code in [1, 2]) {
      final updater = service([entry(code: code)]);
      expect(await updater.check(manifestUrl, 'child'), null);
      updater.dispose();
    }
  });
  test(
    'foreign host, role, signature and invalid amounts are rejected',
    () async {
      for (final change in [
        {'url': 'https://foreign.example/downloads/MyKIDS-child-0.1.2.apk'},
        {'package': 'ru.mykids.mykids_family.child'},
        {'certificate_sha256': List.filled(64, 'b').join()},
        {'version_code': 3.0},
        {'bytes': 1024 * 1024 * 1024},
        {'version': '../malicious'},
      ]) {
        final updater = service([
          {...entry(), ...change},
        ]);
        await expectLater(
          updater.check(manifestUrl, 'child'),
          throwsA(isA<ApiFailure>()),
        );
        updater.dispose();
      }
    },
  );
  test('HTTP and redirects cannot supply an update', () async {
    final updater = AppUpdates(
      client: MockClient((request) async => http.Response('', 302)),
    );
    await expectLater(
      updater.check(manifestUrl, 'child'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      updater.check(
        Uri.parse('http://family.example/downloads/latest.json'),
        'child',
      ),
      throwsA(isA<ApiFailure>()),
    );
    updater.dispose();
  });
  Future<UpdateOffer> offer() async {
    final checker = service([entry()]);
    final result = (await checker.check(manifestUrl, 'child'))!;
    checker.dispose();
    return result;
  }

  test(
    'closing the observer preserves the system download and progress',
    () async {
      final candidate = await offer();
      var state = <String, Object>{
        'state': 'running',
        'id': 42,
        'received': 8,
        'bytes': candidate.bytes,
      };
      messenger.setMockMethodCallHandler(nativeUpdates, (call) async {
        calls.add(call);
        if (call.method == 'startDownload' || call.method == 'downloadStatus') {
          return state;
        }
        throw StateError('Closing the observer must not cancel or install');
      });
      final updater = AppUpdates(pollInterval: const Duration(milliseconds: 5));
      final firstProgress = Completer<void>();
      final watching = updater.download(candidate, (_) {
        if (!firstProgress.isCompleted) firstProgress.complete();
      });
      final assertion = expectLater(watching, throwsA(isA<ApiFailure>()));
      await firstProgress.future;
      updater.dispose();
      await assertion;
      expect(calls.where((c) => c.method == 'startDownload').length, 1);
      expect(calls.any((c) => c.method == 'cancelDownload'), false);

      final restored = AppUpdates(
        pollInterval: const Duration(milliseconds: 5),
      );
      expect(
        (await restored.downloadState(candidate)).progress,
        8 / candidate.bytes,
      );
      state = {
        'state': 'ready',
        'id': 42,
        'received': candidate.bytes,
        'bytes': candidate.bytes,
      };
      await restored.download(candidate, (_) {}, start: false);
      expect(calls.where((c) => c.method == 'startDownload').length, 1);
      expect(calls.any((c) => c.method == 'installUpdate'), false);
      restored.dispose();
    },
  );

  test(
    'a finished background download is reused without another transfer',
    () async {
      final candidate = await offer();
      messenger.setMockMethodCallHandler(nativeUpdates, (call) async {
        calls.add(call);
        if (call.method == 'downloadStatus') {
          return {
            'state': 'ready',
            'received': candidate.bytes,
            'bytes': candidate.bytes,
          };
        }
        if (call.method == 'installUpdate') return 'installer_opened';
        throw StateError('No new download is needed');
      });
      final updater = AppUpdates();
      expect((await updater.downloadState(candidate)).ready, true);
      expect(await updater.install(candidate), 'installer_opened');
      final installation = calls.last.arguments as Map;
      expect(installation['sha256'], candidate.sha);
      expect(installation['versionCode'], candidate.versionCode);
      updater.dispose();
    },
  );

  test(
    'a failed or removed system download cannot be installed automatically',
    () async {
      final candidate = await offer();
      for (final state in ['failed', 'idle']) {
        messenger.setMockMethodCallHandler(nativeUpdates, (call) async {
          calls.add(call);
          if (call.method == 'downloadStatus') {
            return {'state': state, 'message': 'Проверочная ошибка'};
          }
          throw StateError('No automatic restart or installation');
        });
        final updater = AppUpdates();
        await expectLater(
          updater.download(candidate, (_) {}, start: false),
          throwsA(isA<ApiFailure>()),
        );
        updater.dispose();
      }
      expect(
        calls.any(
          (c) => c.method == 'startDownload' || c.method == 'installUpdate',
        ),
        false,
      );
    },
  );

  test(
    'explicit cancellation stops observation and permits a fresh retry',
    () async {
      final candidate = await offer();
      var state = <String, Object>{
        'state': 'paused',
        'id': 42,
        'received': 8,
        'bytes': candidate.bytes,
      };
      messenger.setMockMethodCallHandler(nativeUpdates, (call) async {
        calls.add(call);
        if (call.method == 'cancelDownload') {
          state = {'state': 'idle'};
          return null;
        }
        return state;
      });
      final updater = AppUpdates();
      final firstProgress = Completer<void>();
      final watching = updater.download(candidate, (_) {
        if (!firstProgress.isCompleted) firstProgress.complete();
      }, start: false);
      final assertion = expectLater(watching, throwsA(isA<ApiFailure>()));
      await firstProgress.future;
      await updater.cancelDownload(candidate);
      await assertion;
      expect((await updater.downloadState(candidate)).state, 'idle');
      state = {
        'state': 'ready',
        'received': candidate.bytes,
        'bytes': candidate.bytes,
      };
      await updater.download(candidate, (_) {});
      updater.dispose();
    },
  );
  test(
    'closing an update requests cancellation of native installation',
    () async {
      final candidate = await offer();
      final reply = Completer<String>();
      messenger.setMockMethodCallHandler(nativeUpdates, (call) async {
        calls.add(call);
        return call.method == 'installUpdate' ? reply.future : null;
      });
      final updater = AppUpdates();
      final future = updater.install(candidate);
      final assertion = expectLater(future, throwsA(isA<ApiFailure>()));
      await Future<void>.delayed(Duration.zero);
      updater.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls.any((call) => call.method == 'cancelUpdate'), true);
      reply.complete('installer_opened');
      await assertion;
    },
  );
}
