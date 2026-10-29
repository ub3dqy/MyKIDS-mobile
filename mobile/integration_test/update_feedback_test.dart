import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/updates.dart';
import 'package:mykids_family/visuals.dart';

class FeedbackFixture extends FamilyRepository {
  FeedbackFixture()
    : super(client: MockClient((_) async => http.Response('{}', 200)));
  @override
  Future<void> sync() async {}
  @override
  Future<List<Map<String, Object?>>> pending() async => [];

  void signInSynthetic() {
    token = 'synthetic-unregistered-session';
    online = true;
    snapshot = {
      'user': {'name': 'Проверка', 'role': 'parent'},
      'family': {'timezone': 'Europe/Moscow'},
      'server_time': '2026-10-11T12:00:00Z',
    };
    notifyListeners();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('manual Android checks always display a result', (tester) async {
    final info = (await nativeUpdates.invokeMapMethod<String, dynamic>(
      'appInfo',
    ))!;
    expect(info['package'], 'ru.mykids.mykids_family.parent');
    expect(info['versionCode'], 6);
    final repo = FeedbackFixture()
      ..variant = 'parent'
      ..endpoint = 'https://family.example';
    final initialResponse = Completer<http.Response>();
    int requests = 0, status = 200;
    bool newer = false;

    http.Response response() => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'schema': 1,
          'apps': [
            {
              'role': 'family',
              'package': info['package'],
              'version': newer ? '0.1.6' : '0.1.5',
              'version_code': (info['versionCode'] as int) + (newer ? 1 : 0),
              'bytes': 100,
              'sha256': List.filled(64, 'a').join(),
              'certificate_sha256': info['signerSha256'],
              'notes': 'Искусственное обновление для проверки окна',
              'url':
                  'https://family.example/downloads/MyKIDS-${newer ? '0.1.6' : '0.1.5'}.apk',
            },
          ],
        }),
      ),
      status,
    );

    Future<void> waitFor(Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (finder.evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError(
            'Expected Android UI result did not appear: $finder',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
    }

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpWidget(
      MyKidsApp(
        repository: repo,
        createUpdates: () => AppUpdates(
          client: MockClient((request) async {
            expect(request.headers.containsKey('Authorization'), false);
            expect(request.url.host, 'family.example');
            requests++;
            return requests == 1 ? initialResponse.future : response();
          }),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheFamilyArtwork(tester.element(find.byType(MyKidsApp))),
    );
    await tester.pump();
    await tester.tap(find.text('Проверить обновления приложения'));
    await waitFor(find.text('Проверяем актуальность версии…'));
    expect(requests, 1);
    initialResponse.complete(response());
    await waitFor(find.text('Обновлений нет'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('updates-no-update');
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    repo.signInSynthetic();
    await tester.pumpAndSettle();
    expect(find.text('Обновить'), findsNothing);
    expect(find.text('Обновить данные'), findsNothing);
    expect(find.byTooltip('Настройки'), findsOneWidget);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проверить обновления приложения'));
    await waitFor(find.text('Обновлений нет'));
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    status = 503;
    await tester.tap(find.text('Проверить обновления приложения'));
    await waitFor(find.text('Не удалось проверить обновления'));
    expect(find.text('Обновлений нет'), findsNothing);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('updates-check-error');
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    status = 200;
    newer = true;
    await tester.tap(find.text('Проверить обновления приложения'));
    await waitFor(find.text('Доступно обновление MyKIDS'));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('updates-check-new-version');
    await tester.tap(find.text('Позже'));
    await tester.pumpAndSettle();
    binding.reportData = {
      ...?binding.reportData,
      'manual_joined_automatic_check': true,
      'no_update_message_visible': true,
      'settings_check_message_visible': true,
      'top_refresh_action_absent': true,
      'app_version_code': info['versionCode'],
      'failure_not_misreported_as_no_updates': true,
      'new_version_prompt_visible_once': true,
      'scope': 'Android 16 emulator; actual MyKidsApp and native appInfo, isolated local HTTP responses and synthetic unregistered session. No real family login, server mutation, APK download or installer confirmation; physical phones not exercised.',
    };
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });
}
