import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/updates.dart';

class FixtureRepository extends FamilyRepository {
  @override
  Future<void> sync() async {}
  @override
  Future<List<Map<String, Object?>>> pending() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final certificate = List.filled(64, 'a').join();
  late FixtureRepository repo;
  late Completer<http.Response> response;
  int requests = 0;
  int downloads = 0, installations = 0;
  Map<String, Object> download = {'state': 'idle'};

  http.Response manifest({int code = 3}) => http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'schema': 1,
        'apps': [
          {
            'role': 'family',
            'package': 'ru.mykids.mykids_family.parent',
            'version': '0.1.3',
            'version_code': code,
            'bytes': 100,
            'sha256': List.filled(64, 'b').join(),
            'certificate_sha256': certificate,
            'notes': 'Проверочное обновление',
            'url': 'https://family.example/downloads/MyKIDS-0.1.3.apk',
          },
        ],
      }),
    ),
    200,
  );

  setUp(() {
    repo = FixtureRepository()
      ..variant = 'parent'
      ..endpoint = 'https://family.example';
    response = Completer<http.Response>();
    requests = 0;
    downloads = installations = 0;
    download = {'state': 'idle'};
    messenger.setMockMethodCallHandler(nativeUpdates, (call) async {
      if (call.method == 'appInfo') {
        return {
          'package': 'ru.mykids.mykids_family.parent',
          'versionCode': 3,
          'signerSha256': certificate,
          'updateDirectory': '/unused-synthetic-update-directory',
        };
      }
      if (call.method == 'downloadStatus') return download;
      if (call.method == 'startDownload') {
        downloads++;
        return download = {
          'state': 'running',
          'id': 42,
          'received': 40,
          'bytes': 100,
        };
      }
      if (call.method == 'installUpdate') {
        installations++;
        return 'installer_opened';
      }
      throw StateError('This UI test must not download or install an APK');
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(nativeUpdates, null);
    repo.client.close();
    repo.dispose();
  });

  Future<void> openApp(WidgetTester tester, {bool signedIn = false}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (signedIn) {
      repo
        ..token = 'synthetic-unregistered-session'
        ..online = true
        ..snapshot = {
          'user': {'name': 'Проверка', 'role': 'parent'},
          'family': {'timezone': 'Europe/Moscow'},
          'server_time': '2026-10-11T12:00:00Z',
        };
    }
    await tester.pumpWidget(
      MyKidsApp(
        repository: repo,
        createUpdates: () => AppUpdates(
          client: MockClient((request) async {
            requests++;
            expect(request.headers.containsKey('Authorization'), false);
            return response.future;
          }),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, 1);
  }

  Future<void> tapUpdates(WidgetTester tester) async {
    final button = find.text('Проверить обновления приложения');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> finishResponse(WidgetTester tester, http.Response value) async {
    await tester.runAsync(() async {
      response.complete(value);
      // HTTP response streams must finish before advancing the fake UI clock.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('manual click joins an automatic check and shows no updates', (
    tester,
  ) async {
    await openApp(tester);
    await tapUpdates(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Проверяем актуальность версии…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(requests, 1);
    await finishResponse(tester, manifest());
    expect(find.text('Обновлений нет'), findsOneWidget);
    expect(
      find.text('У вас установлена актуальная версия MyKIDS.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    await tapUpdates(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('Обновлений нет'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    await closeApp(tester);
  });

  testWidgets('automatic current-version checks remain quiet', (tester) async {
    await openApp(tester);
    await finishResponse(tester, manifest());
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Обновлений нет'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('manual failed check is not presented as no updates', (
    tester,
  ) async {
    await openApp(tester);
    await tapUpdates(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await finishResponse(tester, http.Response('temporarily unavailable', 503));
    expect(find.text('Не удалось проверить обновления'), findsOneWidget);
    expect(find.text('Обновлений нет'), findsNothing);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    await closeApp(tester);
  });

  testWidgets('joined manual check displays a new version only once', (
    tester,
  ) async {
    await openApp(tester);
    await tapUpdates(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await finishResponse(tester, manifest(code: 4));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Доступно обновление MyKIDS'), findsOneWidget);
    expect(requests, 1);
    await tester.tap(find.text('Позже'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await closeApp(tester);
  });

  testWidgets('a fresh check failure before the dialog builds is handled', (
    tester,
  ) async {
    await openApp(tester);
    await finishResponse(tester, manifest());
    response = Completer<http.Response>()
      ..complete(http.Response('temporarily unavailable', 503));
    await tapUpdates(tester);
    // The service can fail before the next frame mounts the result dialog.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Не удалось проверить обновления'), findsOneWidget);
    expect(find.text('Обновлений нет'), findsNothing);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    await closeApp(tester);
  });

  testWidgets('settings button shows the same current-version result', (
    tester,
  ) async {
    await openApp(tester, signedIn: true);
    await finishResponse(tester, manifest());
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tapUpdates(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Обновлений нет'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    await closeApp(tester);
  });

  testWidgets(
    'lock, unlock and app recreation keep one transfer and require installation confirmation',
    (tester) async {
      await openApp(tester);
      await finishResponse(tester, manifest(code: 4));
      await tester.tap(find.text('Скачать и обновить'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('40 %'), findsOneWidget);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      download = {'state': 'running', 'id': 42, 'received': 60, 'bytes': 100};
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('60 %'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(downloads, 1);
      expect(requests, 1);
      // Recreating the application loses Dart state but keeps the native job.
      await closeApp(tester);
      requests = 0;
      response = Completer<http.Response>();
      await openApp(tester);
      response.complete(manifest(code: 4));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('60 %'), findsOneWidget);
      expect(downloads, 1);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      download = {'state': 'ready', 'id': 42, 'received': 100, 'bytes': 100};
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Обновление готово'), findsOneWidget);
      expect(installations, 0);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      await tester.tap(find.text('Установить'));
      await tester.pump();
      expect(installations, 1);
      expect(downloads, 1);
      await closeApp(tester);
    },
  );
}
