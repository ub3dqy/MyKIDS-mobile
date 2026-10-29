import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/settings_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual Android settings, notification cleanup and private account removal',
    (tester) async {
      final emulator = await Process.run('/system/bin/getprop', [
        'ro.kernel.qemu',
      ]);
      expect(
        Platform.isAndroid && emulator.stdout.toString().trim() == '1',
        true,
      );
      final support = await getApplicationSupportDirectory();
      Future<void> stage(String name) =>
          File('${support.path}/mykids-quality102-stage.json')
              .writeAsString(jsonEncode({'stage': name}));
      final snapshot = <String, dynamic>{
        'server_time': DateTime.now().toUtc().toIso8601String(),
        'user': {
          'id': 'synthetic-parent',
          'name': 'Проверочный родитель',
          'role': 'parent',
        },
        'family': {
          'id': 'synthetic-family',
          'timezone': 'Europe/Moscow',
          'quiet_start': '22:00',
          'quiet_end': '07:00',
          'day_start': '07:00',
          'day_end': '22:00',
        },
        'members': [
          {
            'id': 'synthetic-relative',
            'name': 'Проверочная бабушка',
            'role': 'relative',
            'create_tasks': 1,
            'view_tasks': 1,
            'review_tasks': 1,
            'active': 1,
            'permissions_revision': 'a' * 64,
          },
        ],
        'tasks': [],
        'schedules': [],
        'schedule_exceptions': [],
        'audit': [],
        'rooms': [],
      };
      final errors = <String>[];
      var changes = 0, remoteLogouts = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final listener = server.listen((request) async {
        try {
          final raw = await request.fold<List<int>>([], (a, b) => a..addAll(b));
          expectSync(raw.length, lessThan(16384));
          request.response.headers.contentType = ContentType.json;
          Object response = {};
          if (request.uri.path == '/v1/login') {
            response = {'token': 'synthetic-android-settings'};
          } else {
            expectSync(
              request.headers.value(HttpHeaders.authorizationHeader),
              'Bearer synthetic-android-settings',
            );
            switch (request.uri.path) {
              case '/v1/snapshot':
                response = snapshot;
              case '/v1/counters':
                response = {'rooms': []};
              case '/v1/members/synthetic-relative':
                expectSync(request.method, 'PATCH');
                expectSync(jsonDecode(utf8.decode(raw)), {
                  'view_tasks': false,
                  'expected_revision': 'a' * 64,
                });
                changes++;
                final member = (snapshot['members'] as List).single as Map;
                member['view_tasks'] = 0;
                member['permissions_revision'] = 'b' * 64;
                response = {'ok': true};
              case '/v1/logout':
                expectSync(request.method, 'POST');
                remoteLogouts++;
                response = {'ok': true};
              default:
                throw StateError('Unexpected test route: ${request.uri.path}');
            }
          }
          request.response.write(jsonEncode(response));
          await request.response.close();
        } catch (error) {
          errors.add(error.toString());
          request.response.statusCode = 500;
          request.response.write('{}');
          await request.response.close();
        }
      });
      final repo = FamilyRepository();
      final background = BackgroundServices(repo);
      Future<void> press(String label, {bool settle = true}) async {
        final found = find.text(label);
        await tester.scrollUntilVisible(
          found,
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(found);
        await tester.pumpAndSettle();
        expect(found.hitTestable(), findsOneWidget);
        await tester.tap(found.hitTestable());
        if (settle) await tester.pumpAndSettle();
      }

      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 200 && !condition(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), true);
      }

      Future<void> screenshot(String name) async {
        final bytes = await binding.takeScreenshot('settings-$name');
        expect(bytes, isNotEmpty);
        await File('${support.path}/mykids-quality102-$name.png')
            .writeAsBytes(bytes);
      }

      try {
        await repo.initialize();
        await repo.login(
          'http://127.0.0.1:${server.port}',
          'synthetic-settings',
          'local-only-password',
        );
        await initializeNotifications();
        tzdata.initializeTimeZones();
        await notifications.zonedSchedule(
          id: 1000100102,
          title: 'MyKIDS',
          body: 'Искусственное напоминание',
          scheduledDate: tz.TZDateTime.now(tz.UTC).add(const Duration(days: 1)),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'quality102',
              'Локальная проверка',
              visibility: NotificationVisibility.private,
            ),
          ),
        );
        expect(
          (await notifications.pendingNotificationRequests()).where(
            (n) => n.id == 1000100102,
          ),
          hasLength(1),
        );
        final source = File('${support.path}/synthetic-quality102-note.txt');
        await source.writeAsString(
          'Synthetic private attachment; no family data',
        );
        final kept = await repo.keepFile(source.path);
        expect(await File(kept).exists(), true);
        await source.delete();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Настройки семьи')),
              body: AnimatedBuilder(
                animation: repo,
                builder: (context, _) => repo.signedIn
                    ? SettingsScreen(
                        repository: repo,
                        background: background,
                        perform: (action) async {
                          await action();
                        },
                        onUpdates: () async {},
                      )
                    : const Center(child: Text('Вы вышли из аккаунта')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await screenshot('initial');
        for (final item in const {
          'notifications': 'Настройки уведомлений телефона',
          'battery': 'Настройки работы в фоне',
          'fullscreen': 'Показ входящих звонков на экране',
        }.entries) {
          await stage('settings-${item.key}');
          await press(item.value, settle: false);
          final ack = File('${support.path}/mykids-quality102-${item.key}.ack');
          var acknowledged = false;
          for (var i = 0; i < 300; i++) {
            if (await ack.exists() &&
                await ack.readAsString() == 'verified-return') {
              acknowledged = true;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(
            acknowledged,
            true,
            reason: 'The actual Android settings screen must be observed and returned from',
          );
          await tester.pumpAndSettle();
        }
        await press('Проверочная бабушка');
        await press('Смотреть свои задания');
        await waitFor(
          () => changes == 1 && repo.rows('members').single['view_tasks'] == 0,
        );
        expect(repo.rows('members').single['active'], 1);
        expect(repo.rows('members').single['create_tasks'], 1);
        expect(repo.rows('members').single['review_tasks'], 1);
        await screenshot('permissions');
        await repo.db!.insert('outbox', {
          'id': 'synthetic-private-pending',
          'path': '/v1/tasks/test',
          'method': 'POST',
          'body': '{}',
          'files': '[]',
          'state': 'pending',
          'auth_tag': repo.sessionTag,
        });
        expect(await repo.db!.query('cache'), isNotEmpty);
        await press('Выйти и удалить данные с телефона');
        await waitFor(() => !repo.signedIn);
        for (
          var i = 0;
          i < 100 &&
              (await notifications.pendingNotificationRequests()).isNotEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(await repo.storage.read(key: 'session'), isNull);
        for (final table in ['cache', 'identity', 'outbox']) {
          expect(await repo.db!.query(table), isEmpty);
        }
        expect(await File(kept).exists(), false);
        expect(await notifications.pendingNotificationRequests(), isEmpty);
        expect(remoteLogouts, 1);
        expect(errors, isEmpty);
        await screenshot('signed-out');
        await File('${support.path}/mykids-quality102-proof.json')
            .writeAsString(
              jsonEncode({
                'actual_android': true,
                'real_native_settings_intents': true,
                'actual_secure_storage_cleared': true,
                'actual_sqlite_private_rows_deleted': true,
                'actual_private_attachment_deleted': true,
                'actual_android_alarm_canceled': true,
                'actual_logout_http_request': true,
                'actual_partial_permission_http_request': true,
                'larger_text': true,
                'synthetic_only': true,
                'physical_phone': false,
              }),
            );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        background.dispose();
        await repo.db?.close();
        repo.client.close();
        repo.dispose();
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );
}
