import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/invitation.dart';
import 'package:mykids_family/invitation_dialog.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/school_screen.dart';
import 'package:mykids_family/settings_screen.dart';
import 'package:mykids_family/visuals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:uuid/uuid.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual calendar grade corrections, full-height list and Android invitation copying',
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
      final support = await getApplicationSupportDirectory();
      final repo = FamilyRepository();
      final background = BackgroundServices(repo);
      final transport = http.Client();
      final decoder = MobileScannerController(autoStart: false);
      final errors = <Object>[];
      final tokens = <String>{};
      final qrFile = File('${support.path}/mykids-quality105-qr.png');

      Future<void> perform(
        Future<Map<String, dynamic>> Function() action,
      ) async {
        try {
          await action();
        } catch (error) {
          errors.add(error);
        }
      }

      Future<void> stage(String name) async {
        // A resumed test surface needs a pumped frame before OS capture.
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        await File('${support.path}/mykids-quality105-stage.json')
            .writeAsString(jsonEncode({'stage': name}));
        final ack = File('${support.path}/mykids-quality105-continue-$name');
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (!await ack.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Android coordinator timed out: $name');
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await ack.delete();
      }

      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Android UI did not reach expected state');
          }
          await tester.pump(const Duration(milliseconds: 150));
        }
        await tester.pumpAndSettle();
      }

      Future<void> reveal(Finder finder) async {
        await tester.scrollUntilVisible(
          finder,
          250,
          maxScrolls: 80,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      Future<Map<String, dynamic>> command(
        String path,
        Map<String, dynamic> body, {
        String method = 'POST',
      }) async {
        final request = http.Request(method, Uri.parse('$endpoint$path'))
          ..headers.addAll({
            'Authorization': 'Bearer ${repo.token}',
            'Content-Type': 'application/json',
            'Idempotency-Key': const Uuid().v4(),
          })
          ..body = jsonEncode(body);
        final response = await http.Response.fromStream(
          await transport.send(request),
        );
        expect(response.statusCode, 200, reason: response.body);
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      }

      Future<void> mount(Widget child) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(
          MaterialApp(
            theme: familyTheme(false),
            locale: const Locale('ru'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('ru')],
            home: Scaffold(body: child),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> settings() => mount(
        SettingsScreen(
          repository: repo,
          background: background,
          perform: perform,
          onUpdates: () async {},
        ),
      );

      try {
        await repo.initialize();
        await repo.selectRole('parent');
        await repo.login(
          endpoint,
          'quality105-parent',
          'synthetic-native-grade-123',
        );
        for (final (role, button) in [
          ('child', 'Подключить ребёнка'),
          ('parent', 'Подключить второго родителя'),
          ('relative', 'Подключить бабушку или дедушку'),
        ]) {
          await settings();
          final opener = find.text(button);
          await reveal(opener);
          await tester.tap(opener);
          await until(
            () => find.byType(InvitationDialog).evaluate().isNotEmpty,
          );
          final dialog = tester.widget<InvitationDialog>(
            find.byType(InvitationDialog),
          );
          expect(dialog.invitation.role, role);
          final token = dialog.invitation.token;
          expect(tokens.add(token), true);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('invitation-qr')),
          );
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await qrFile.writeAsBytes(bytes!.buffer.asUint8List());
          final capture = await decoder.analyzeImage(
            qrFile.path,
            formats: const [BarcodeFormat.qrCode],
          );
          expect(capture!.barcodes.single.rawValue, dialog.invitation.qrData);
          final parsed = Invitation.parse(
            capture.barcodes.single.rawValue!,
            expectedRole: role,
          );
          expect(parsed.role, role);
          expect(parsed.token, token);
          await tester.tap(find.widgetWithText(TextButton, 'Скопировать'));
          await until(() => find.text('Код скопирован').evaluate().isNotEmpty);
          expect((await Clipboard.getData(Clipboard.kTextPlain))!.text, token);
          await stage('invite-$role');
          final payload = {
            'token': token,
            'username': 'quality105-$role-invited',
            'name': 'Проверка $role',
            'password': 'synthetic-invited-123',
          };
          final accepted = await transport.post(
            Uri.parse('$endpoint/v1/invites/accept'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
          expect(accepted.statusCode, 200, reason: accepted.body);
          final acceptedToken = (jsonDecode(accepted.body) as Map)['token'];
          final snap = await transport.get(
            Uri.parse('$endpoint/v1/snapshot'),
            headers: {'Authorization': 'Bearer $acceptedToken'},
          );
          expect((jsonDecode(snap.body) as Map)['user']['role'], role);
          final replay = await transport.post(
            Uri.parse('$endpoint/v1/invites/accept'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              ...payload,
              'username': 'quality105-replay-$role',
            }),
          );
          expect(replay.statusCode, 403);
          await tester.tap(find.widgetWithText(TextButton, 'Закрыть'));
          await until(() => find.byType(InvitationDialog).evaluate().isEmpty);
        }
        expect(tokens, hasLength(3));
        await command('/v1/grade-rules', {
          'amounts': {'5': 25, '4': 10, '3': 0, '2': -40},
        }, method: 'PUT');
        final school = await command('/v1/schedules', {
          'title': 'Школа',
          'date': null,
          'weekdays': [1, 2, 3, 4, 5],
          'start': '08:00',
          'end': '14:00',
          'kind': 'school',
          'color': 'blue',
          'activities': [
            for (var i = 0; i < 6; i++)
              {
                'title': 'Проверочный предмет ${i + 1}',
                'start': '${(8 + i).toString().padLeft(2, '0')}:00',
                'end': '${(8 + i).toString().padLeft(2, '0')}:40',
              },
          ],
        });
        for (var i = 0; i < 2; i++) {
          await command('/v1/tasks', {
            'title': 'Субботнее задание ${i + 1}',
            'due_at': '2026-10-24T${17 + i}:00:00+03:00',
            'reward': 5,
          });
        }
        await repo.sync();
        final sid = school['id'];
        final activities = jsonDecode(
          repo.rows('schedules').single['activities'] as String,
        ) as List;
        final aid = activities.first['id'];
        final firstButton = find.byKey(
          ValueKey('result-grade-schedule:$sid:2026-10-23:$aid'),
        );
        await mount(
          CalendarScreen(
            repository: repo,
            perform: perform,
            openTasks: (_) {},
            initialDay: DateTime(2026, 10, 23),
          ),
        );
        final openGrades = find.text('Предметы и оценки');
        await reveal(openGrades);
        await tester.tap(openGrades);
        await tester.pumpAndSettle();
        expect(find.byType(SchoolScreen), findsOneWidget);
        expect(find.byType(Scrollable), findsOneWidget);
        final viewport = tester.getRect(find.byType(Scrollable));
        expect(
          viewport.bottom,
          greaterThan(
            tester.view.physicalSize.height / tester.view.devicePixelRatio - 90,
          ),
        );
        await reveal(find.text('Проверочный предмет 6'));
        await stage('grade-weekday');
        await tester.drag(find.byType(Scrollable), const Offset(0, 5000));
        await tester.pumpAndSettle();
        await reveal(firstButton);
        await tester.tap(firstButton);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('5').last);
        await tester.pumpAndSettle();
        await reveal(find.text('Сохранить'));
        await tester.tap(find.text('Сохранить'));
        await until(() => find.byType(FamilyForm).evaluate().isEmpty);
        expect(repo.rows('grades').single['grade'], 5);
        expect(repo.snapshot!['balance']['total'], 25);
        await reveal(firstButton);
        await tester.tap(firstButton);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('4').last);
        await tester.pumpAndSettle();
        await reveal(find.text('Сохранить'));
        await tester.tap(find.text('Сохранить'));
        await until(() => find.byType(FamilyForm).evaluate().isEmpty);
        expect(repo.rows('grades').single['grade'], 4);
        expect(repo.rows('penalties').single['amount'], 15);
        await reveal(firstButton);
        await stage('grade-edited');
        final gid = repo.rows('grades').single['id'];
        final delete = find.byKey(ValueKey('result-delete-grade-$gid'));
        await reveal(delete);
        await tester.tap(delete);
        await tester.pumpAndSettle();
        await stage('grade-delete-confirm');
        final confirm = find.byKey(const ValueKey('confirm-delete-grade'));
        await reveal(confirm);
        await tester.tap(confirm);
        await until(() => repo.rows('grades').isEmpty);
        expect(repo.snapshot!['balance']['total'], 0);
        expect(repo.rows('penalties').single['status'], 'waived');
        expect(repo.rows('ledger').map((r) => r['actual']).toList()..sort(), [
          -25,
          25,
        ]);
        await stage('grade-deleted');
        await tester.tap(find.byTooltip('Следующий день'));
        await tester.pumpAndSettle();
        expect(find.byType(Scrollable), findsOneWidget);
        await reveal(find.text('Субботнее задание 2'));
        await stage('grade-weekend');
        expect(errors, isEmpty);
        await settings();
        await reveal(find.text('Подключить ребёнка'));
        await tester.tap(find.text('Подключить ребёнка'));
        await until(() => find.byType(InvitationDialog).evaluate().isNotEmpty);
        await stage('invite-before-background');
        await stage('invite-after-background');
        expect(find.byKey(const ValueKey('invitation-qr')), findsOneWidget);
        await repo.logout(remote: false);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('invitation-qr')), findsNothing);
        expect(find.text('Скопировать'), findsNothing);
        await stage('invite-invalidated');
        await tester.tap(find.widgetWithText(TextButton, 'Закрыть'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await File('${support.path}/mykids-quality105-proof.json')
            .writeAsString(
              jsonEncode({
                'actual_calendar_entry': true,
                'weekday_full_height': true,
                'weekend_full_height': true,
                'grade_created': true,
                'grade_edited': true,
                'grade_deleted': true,
                'exact_coin_reversal': true,
                'pending_penalty_cancelled': true,
                'three_actual_invitation_roles': true,
                'android_mlkit_qr_decode': true,
                'production_clipboard_channel': true,
                'invitation_single_use': true,
                'invitation_survives_same_account_resume': true,
                'logout_hides_invitation': true,
                'physical_phone': false,
              }),
            );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (await qrFile.exists()) await qrFile.delete();
        await decoder.dispose();
        background.dispose();
        await repo.db?.close();
        repo.client.close();
        repo.dispose();
        transport.close();
      }
    },
  );
}
