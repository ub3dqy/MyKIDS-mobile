import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'cancel a real waiting HTTP login and retry on isolated Android',
    (tester) async {
      final emulator = await Process.run('/system/bin/getprop', [
        'ro.kernel.qemu',
      ]);
      expect(
        Platform.isAndroid && emulator.stdout.toString().trim() == '1',
        true,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final support = await getApplicationSupportDirectory();
      final firstEntered = Completer<void>(), releaseFirst = Completer<void>();
      var logins = 0, callbacks = 0;
      final listener = server.listen((request) async {
        try {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path == '/v1/login') {
            final attempt = ++logins;
            if (attempt == 1) {
              firstEntered.complete();
              await releaseFirst.future;
            }
            request.response.write(
              jsonEncode({'token': 'synthetic-android-$attempt'}),
            );
          } else if (request.uri.path == '/v1/snapshot') {
            request.response.write(
              jsonEncode({
                'user': {
                  'id': 'synthetic-android-child',
                  'name': 'Тестовый ребёнок',
                  'role': 'child',
                },
              }),
            );
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('{}');
          }
          await request.response.close();
        } on SocketException {
          // Expected when the first real HTTP transport is cancelled.
        } on HttpException {
          // The aborted peer can close before the held response is written.
        }
      });
      final repo = FamilyRepository();
      try {
        await repo.initialize();
        await repo.logout(remote: false);
        repo.endpoint = 'http://127.0.0.1:${server.port}';
        await repo.selectRole('child');
        await tester.pumpWidget(
          MaterialApp(
            home: LoginScreen(
              repository: repo,
              onLogin: () async {
                callbacks++;
              },
              onUpdates: () async {},
            ),
          ),
        );
        for (final field in ['username', 'password']) {
          final finder = find.byKey(ValueKey('login-$field'));
          await tester.scrollUntilVisible(
            finder,
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(
            finder,
            field == 'username' ? 'synthetic' : 'local-only-password',
          );
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, 'Войти'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
        await tester.pump(const Duration(milliseconds: 200));
        await firstEntered.future.timeout(const Duration(seconds: 10));
        await tester.scrollUntilVisible(
          find.text('Отменить подключение'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        final pendingImage = await binding.takeScreenshot(
          'android-login-pending',
        );
        expect(pendingImage, isNotEmpty);
        await File('${support.path}/mykids-quality100-pending.png')
            .writeAsBytes(pendingImage);
        final elapsed = Stopwatch()..start();
        await tester.tap(find.text('Отменить подключение'));
        await tester.pumpAndSettle();
        elapsed.stop();
        expect(elapsed.elapsed, lessThan(const Duration(seconds: 3)));
        expect(find.text('Подключение…'), findsNothing);
        expect(repo.signedIn, false);
        expect(await repo.storage.read(key: 'session'), isNull);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('login-password')),
              )
              .controller!
              .text,
          'local-only-password',
        );
        releaseFirst.complete();
        await tester.pump(const Duration(milliseconds: 300));
        expect(callbacks, 0);
        final cancelledImage = await binding.takeScreenshot(
          'android-login-cancelled',
        );
        expect(cancelledImage, isNotEmpty);
        await File('${support.path}/mykids-quality100-cancelled.png')
            .writeAsBytes(cancelledImage);
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, 'Войти'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
        for (var attempt = 0; attempt < 50 && callbacks == 0; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(callbacks, 1);
        expect(logins, 2);
        expect(repo.token, 'synthetic-android-2');
        expect(repo.userId, 'synthetic-android-child');
        expect(await repo.storage.read(key: 'session'), 'synthetic-android-2');
        expect(await repo.db!.query('cache'), hasLength(1));
        binding.reportData = {
          ...?binding.reportData,
          'real_android_http_transport': true,
          'cancel_did_not_wait_for_server': true,
          'cancel_milliseconds': elapsed.elapsedMilliseconds,
          'credentials_retained_in_form': true,
          'late_response_ignored': true,
          'retry_saved_new_session_and_cache': true,
          'physical_phone': false,
          'synthetic_only': true,
        };
      } finally {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await repo.logout(remote: false);
        await repo.db?.close();
        repo.client.close();
        repo.dispose();
        await listener.cancel();
        await server.close(force: true);
      }
      final report = Map<String, dynamic>.from(binding.reportData!)
        ..remove('screenshots');
      await File('${support.path}/mykids-quality100-proof.json')
          .writeAsString(jsonEncode(report));
    },
  );
}
