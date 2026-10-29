import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart' show backgroundSync;
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real Android task and reward forms preserve their owner and durable command',
    (tester) async {
      final emulator = await Process.run('/system/bin/getprop', [
        'ro.kernel.qemu',
      ]);
      expect(
        Platform.isAndroid && emulator.stdout.toString().trim() == '1',
        true,
      );
      expect(gameDesign.value?.id, 'islands');
      tzdata.initializeTimeZones();
      HttpOverrides.global = null;
      const endpoint = 'http://127.0.0.1:18803';
      const password = 'synthetic-native-tasks-123';
      final support = await getApplicationSupportDirectory();
      final repo = FamilyRepository();
      final transport = http.Client();
      final errors = <Object>[];

      Future<void> perform(
        Future<Map<String, dynamic>> Function() action,
      ) async {
        try {
          await action();
        } catch (error) {
          errors.add(error);
        }
      }

      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Android did not reach the required UI state');
          }
          await tester.pump(const Duration(milliseconds: 150));
        }
        await tester.pumpAndSettle();
      }

      Future<void> reveal(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.scrollUntilVisible(
          finder,
          230,
          maxScrolls: 80,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      Future<void> tap(Finder finder) async {
        await reveal(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> back() async {
        final button = find.byType(BackButton);
        expect(button, findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      Future<void> stage(String name) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        await File('${support.path}/mykids-quality106-stage.json')
            .writeAsString(jsonEncode({'stage': name}));
        final ack = File('${support.path}/mykids-quality106-continue-$name');
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (!await ack.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native coordinator timed out at $name');
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await ack.delete();
      }

      Future<Map<String, dynamic>> raw(
        String path,
        Map<String, dynamic> body, {
        String? token,
        bool control = false,
      }) async {
        final response = await transport.post(
          Uri.parse('$endpoint$path'),
          headers: {
            'Content-Type': 'application/json',
            'Idempotency-Key': const Uuid().v4(),
            if (token != null) 'Authorization': 'Bearer $token',
            if (control) 'X-MyKIDS-QA': 'quality106-loopback-only',
          },
          body: jsonEncode(body),
        );
        expect(response.statusCode, 200, reason: response.body);
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      }

      Future<Map<String, dynamic>> stats() async {
        final response = await transport.get(
          Uri.parse('$endpoint/quality106/stats'),
          headers: {'X-MyKIDS-QA': 'quality106-loopback-only'},
        );
        expect(response.statusCode, 200);
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      }

      Future<void> mount({bool money = false}) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: familyTheme(false),
            locale: const Locale('ru'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('ru')],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('MyKIDS')),
              body: AnimatedBuilder(
                animation: repo,
                builder: (_, _) {
                  if (repo.snapshot == null) {
                    return const Center(child: Text('Семейный доступ закрыт'));
                  }
                  return money
                      ? MoneyScreen(repository: repo, perform: perform)
                      : TaskScreen(repository: repo, perform: perform);
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> login(String account, {String role = 'parent'}) async {
        if (repo.signedIn) await repo.logout(remote: false);
        await repo.selectRole(role);
        await repo.login(endpoint, 'quality106-$account', password);
        await tester.pumpAndSettle();
      }

      Future<String> photo(String task, String token, Color color) async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawRect(const Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = color);
        final picture = recorder.endRecording();
        final image = await picture.toImage(8, 8);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        image.dispose();
        picture.dispose();
        const boundary = 'mykids-quality106-photo';
        final crlf = String.fromCharCodes([13, 10]);
        final request =
            http.Request(
                'POST',
                Uri.parse(
                  '$endpoint/v1/attachments?context_type=task&context_id=$task',
                ),
              )
              ..headers.addAll({
                'Authorization': 'Bearer $token',
                'Content-Type': 'multipart/form-data; boundary=$boundary',
              })
              ..bodyBytes = [
                ...utf8.encode(
                  '--$boundary${crlf}Content-Disposition: form-data; name="file"; filename="page.png"${crlf}Content-Type: image/png$crlf$crlf',
                ),
                ...bytes,
                ...utf8.encode('$crlf--$boundary--$crlf'),
              ];
        final response = await http.Response.fromStream(
          await transport.send(request),
        );
        expect(response.statusCode, 200, reason: response.body);
        return (jsonDecode(response.body) as Map)['id'] as String;
      }

      try {
        await repo.initialize();
        await Workmanager().initialize(backgroundSync);
        await login('parent');
        await mount();
        await tap(find.text('Добавить задание'));
        await tester.enterText(
          find.byKey(const ValueKey('field-title')),
          'Задание 106',
        );
        await reveal(find.byKey(const ValueKey('field-penalty')));
        await tester.enterText(
          find.byKey(const ValueKey('field-penalty')),
          '5',
        );
        await tap(find.text('Сохранить'));
        await until(
          () =>
              find.byType(FamilyForm).evaluate().isEmpty &&
              repo.rows('tasks').length == 1,
        );
        final originalTaskId = repo.rows('tasks').single['id'];
        await stage('task-created');
        await tap(find.text('Задание 106'));
        await tap(find.text('Редактировать задание'));
        await tester.enterText(
          find.byKey(const ValueKey('field-title')),
          'Скрываемый черновик',
        );
        await reveal(find.byKey(const ValueKey('field-title')));
        await stage('task-draft-before-background');
        await tester.pumpAndSettle();
        expect(find.text('Скрываемый черновик'), findsOneWidget);
        await stage('task-draft-resumed');
        await login('other');
        await until(
          () => find.textContaining('доступ измен').evaluate().isNotEmpty,
        );
        expect(find.text('Скрываемый черновик'), findsNothing);
        expect(find.byKey(const ValueKey('field-title')), findsNothing);
        await stage('task-access-invalid');
        await back();
        await tester.pumpAndSettle();
        expect(repo.rows('tasks').single['id'], originalTaskId);
        expect(repo.rows('tasks').single['title'], 'Задание 106');

        for (final mode in ['before', 'after']) {
          await mount(money: true);
          await raw('/quality106/fault?mode=$mode', {}, control: true);
          await tap(find.text('Добавить награду'));
          final title = 'Награда 106 $mode';
          await tester.enterText(
            find.byKey(const ValueKey('field-title')),
            title,
          );
          await reveal(find.byKey(const ValueKey('field-price')));
          await tester.enterText(
            find.byKey(const ValueKey('field-price')),
            '25',
          );
          if (mode == 'before') await stage('reward-draft');
          await tap(find.text('Сохранить'));
          await until(
            () => find
                .textContaining('Запрос сохранён на устройстве')
                .evaluate()
                .isNotEmpty,
          );
          expect(find.text('Сохранить'), findsNothing);
          expect(find.widgetWithText(FilledButton, 'Закрыть'), findsOneWidget);
          await stage('reward-queued-$mode');
          await raw('/quality106/fault?mode=off', {}, control: true);
          for (var attempt = 0; attempt < 25; attempt++) {
            await repo.sync();
            if (!(await repo.pending()).any(
              (row) => row['state'] == 'pending',
            )) {
              break;
            }
            await tester.pump(const Duration(milliseconds: 250));
          }
          expect(
            (await repo.pending()).where((row) => row['state'] == 'pending'),
            isEmpty,
          );
          expect(
            repo.rows('rewards').where((row) => row['title'] == title),
            hasLength(1),
          );
          final current = await stats();
          expect((current['reward_counts'] as Map)[title], 1);
          final keys =
              ((current['batches'] as List).last as Map)['keys'] as List;
          expect(keys.length, greaterThanOrEqualTo(2));
          expect(keys.toSet(), hasLength(1));
          await tap(find.widgetWithText(FilledButton, 'Закрыть'));
          await reveal(find.text('$title · 25 монет'));
          await stage('reward-confirmed-$mode');
        }

        final task =
            (await raw('/v1/tasks', {
                  'title': 'Две страницы 106',
                  'due_at': '2030-01-01T15:00:00Z',
                  'reward': 0,
                  'is_required': false,
                  'require_photo': true,
                  'required_photos': 1,
                }, token: repo.token))['ids'][0]
                as String;
        final child =
            (await raw('/v1/login', {
                  'username': 'quality106-child',
                  'password': password,
                }))['token']
                as String;
        final first = await photo(task, child, Colors.white);
        final second = await photo(task, child, Colors.blue);
        expect(first, isNot(second));
        final submission = (await raw('/v1/tasks/$task/submissions', {
          'task_version': 1,
          'marked_at': DateTime.now().toUtc().toIso8601String(),
          'attachment_ids': [first],
          'note': 'Первая страница',
        }, token: child))['id'];
        await repo.sync();
        await mount();
        await tap(find.text('Две страницы 106'));
        await tap(find.text('Нужно исправить'));
        await tester.enterText(
          find.byKey(const ValueKey('field-note')),
          'Старое замечание',
        );
        await raw('/v1/tasks/$task/submission-photos', {
          'task_version': 1,
          'submission_id': submission,
          'attachment_ids': [second],
        }, token: child);
        await tap(find.text('Сохранить'));
        await until(
          () => find
              .textContaining('Результат или условия задания изменились')
              .evaluate()
              .isNotEmpty,
        );
        expect(
          repo.rows('tasks').firstWhere((row) => row['id'] == task)['status'],
          'submitted',
        );
        expect(
          jsonDecode(
            repo
                    .rows('submissions')
                    .firstWhere(
                      (row) => row['id'] == submission,
                    )['attachment_ids']
                as String,
          ),
          [first, second],
        );
        await reveal(
          find.textContaining('Результат или условия задания изменились'),
        );
        await stage('task-return-stale');
        await back();
        await tester.pumpAndSettle();
        await tap(find.text('Нужно исправить'));
        await tester.enterText(
          find.byKey(const ValueKey('field-note')),
          'Проверь второй ответ',
        );
        await tap(find.text('Сохранить'));
        await until(
          () =>
              find.byType(FamilyForm).evaluate().isEmpty &&
              repo
                      .rows('tasks')
                      .firstWhere((row) => row['id'] == task)['status'] ==
                  'returned',
        );
        expect(repo.snapshot!['balance']['total'], 0);
        await stage('task-return-current');

        await login('relative', role: 'relative');
        await mount();
        await tap(find.text('Добавить задание'));
        await tester.enterText(
          find.byKey(const ValueKey('field-title')),
          'Неотправляемый черновик 106',
        );
        await raw('/quality106/permission?enabled=false', {}, control: true);
        await repo.sync();
        await tester.pumpAndSettle();
        expect(find.textContaining('доступ измен'), findsOneWidget);
        await raw('/quality106/permission?enabled=true', {}, control: true);
        await repo.sync();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('field-title')), findsNothing);
        expect(find.text('Неотправляемый черновик 106'), findsNothing);
        await stage('relative-access-invalid');
        final finalStats = await stats();
        expect(finalStats['returns'], [
          {'version': 1, 'status': 409},
          {'version': 2, 'status': 200},
        ]);
        expect((finalStats['reward_counts'] as Map).values, everyElement(1));
        expect(errors, isEmpty);
        await File('${support.path}/mykids-quality106-server-stats.json')
            .writeAsString(jsonEncode(finalStats));
        await File('${support.path}/mykids-quality106-proof.json')
            .writeAsString(
              jsonEncode({
                'actual_task_creation': true,
                'task_draft_same_account_resume': true,
                'old_task_form_hidden': true,
                'no_cross_account_write': true,
                'queued_status_readable': true,
                'durable_queue_no_duplicates_before_commit': true,
                'durable_queue_no_duplicates_after_commit': true,
                'result_version_conflict_preserves_photos': true,
                'reopened_result_returned': true,
                'relative_permission_invalidation': true,
                'physical_phone': false,
              }),
            );
      } finally {
        await Workmanager().cancelAll();
        await tester.pumpWidget(const SizedBox.shrink());
        await repo.db?.close();
        repo.client.close();
        repo.dispose();
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
