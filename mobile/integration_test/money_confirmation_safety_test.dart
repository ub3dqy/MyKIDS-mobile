import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/visuals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:uuid/uuid.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Android money consent and device credentials', (
    tester,
  ) async {
    final emulator = await Process.run('/system/bin/getprop', [
      'ro.kernel.qemu',
    ]);
    expect(
      Platform.isAndroid && emulator.stdout.toString().trim() == '1',
      true,
    );
    tzdata.initializeTimeZones();
    HttpOverrides.global = null;
    const endpoint = 'http://127.0.0.1:18803';
    const password = 'synthetic-native-financial-123';
    final support = await getApplicationSupportDirectory();
    final transport = http.Client();
    final repo = FamilyRepository();
    final errors = <Object>[];
    var completed = 0;

    Future<String> login(String role) async {
      final response = await transport.post(
        Uri.parse('$endpoint/v1/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': 'quality104-$role',
          'password': password,
        }),
      );
      expect(response.statusCode, 200);
      return (jsonDecode(response.body) as Map)['token'] as String;
    }

    Future<Map<String, dynamic>> command(
      String token,
      String path,
      Map<String, dynamic> data, {
      String method = 'POST',
    }) async {
      final request = http.Request(method, Uri.parse('$endpoint$path'))
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Idempotency-Key': const Uuid().v4(),
        })
        ..body = jsonEncode(data);
      final response = await http.Response.fromStream(
        await transport.send(request),
      );
      expect(response.statusCode, 200, reason: response.body);
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }

    Future<void> stage(String name) async {
      final signal = File('${support.path}/mykids-quality104-continue-$name');
      await File('${support.path}/mykids-quality104-stage.json')
          .writeAsString(jsonEncode({'stage': name}));
      final limit = DateTime.now().add(const Duration(seconds: 90));
      while (!await signal.exists()) {
        if (DateTime.now().isAfter(limit)) {
          fail('Owned Android coordinator: $name');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await signal.delete();
    }

    Future<void> finished(int count) async {
      for (var i = 0; i < 160 && completed < count; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(completed, count);
      await tester.pumpAndSettle();
    }

    Future<void> open({bool payout = false}) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(false),
          locale: const Locale('ru'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('ru')],
          home: AnimatedBuilder(
            animation: repo,
            builder: (_, _) => Scaffold(
              body: repo.snapshot == null
                  ? const Center(child: Text('Семейный доступ изменён'))
                  : MoneyScreen(
                      repository: repo,
                      perform: (action) async {
                        try {
                          await action();
                        } catch (error) {
                          errors.add(error);
                        } finally {
                          completed++;
                        }
                      },
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> reveal(Finder finder) async {
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      if (payout) {
        final row = find.text('Выдача рублей · 25');
        await reveal(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
      }
      final action = find.text(
        payout ? 'Уже выдал — подтвердить' : 'Применить',
      );
      await reveal(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    Future<void> approve() async {
      final button = find.widgetWithText(FilledButton, 'Подтвердить');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 300));
    }

    try {
      await repo.initialize();
      await repo.selectRole('parent');
      await repo.login(endpoint, 'quality104-parent', password);
      final parent = repo.token!;
      final child = await login('child');
      final created = await command(parent, '/v1/tasks', {
        'title': 'Проверочные монеты',
        'due_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        'reward': 100,
      });
      final task = (created['ids'] as List).single;
      await command(child, '/v1/tasks/$task/submissions', {
        'task_version': 1,
        'marked_at': DateTime.now().toUtc().toIso8601String(),
      });
      await command(parent, '/v1/tasks/$task/actions', {'action': 'approve'});
      final subject = (await command(parent, '/v1/subjects', {
        'name': 'Проверочная математика',
      }))['id'];
      await command(parent, '/v1/grade-rules', {
        'amounts': {'2': -15},
      }, method: 'PUT');
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await command(parent, '/v1/grades', {
        'subject_id': subject,
        'date': today,
        'grade': 2,
      });
      final request = (await command(child, '/v1/redemptions', {
        'amount': 25,
      }))['id'];
      await command(parent, '/v1/redemptions/$request/actions', {
        'action': 'claim',
      });
      await repo.sync();
      expect(repo.snapshot!['balance']['total'], 100);
      expect(repo.rows('penalties').single['amount'], 15);

      await open();
      await approve();
      await finished(1);
      expect(errors.single, isA<ApiFailure>());
      expect(errors.single.toString(), contains('PIN'));
      expect(repo.snapshot!['balance']['total'], 100);
      // The coordinator configures a synthetic PIN only on this owned guest.
      // Display the real user message for visual inspection.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: Text(errors.single.toString()))),
        ),
      );
      await tester.pumpAndSettle();
      await stage('no-pin');
      errors.clear();

      await open();
      await stage('penalty-consent');
      await approve();
      await stage('cancel-prompt');
      await finished(2);
      expect(errors.single, isA<ApiFailure>());
      expect(errors.single.toString(), contains('отменено'));
      await repo.sync();
      expect(repo.snapshot!['balance']['total'], 100);
      expect(repo.rows('penalties').single['status'], 'pending');
      errors.clear();

      await open();
      await approve();
      await stage('penalty-pin');
      await finished(3);
      expect(errors, isEmpty);
      expect(repo.snapshot!['balance']['total'], 85);
      expect(repo.rows('penalties').single['status'], 'applied');
      expect(
        repo.rows('ledger').where((row) => row['actual'] == -15),
        hasLength(1),
      );

      await open(payout: true);
      await stage('payout-consent');
      await approve();
      await stage('payout-pin');
      await finished(4);
      expect(errors, isEmpty);
      expect(repo.snapshot!['balance']['total'], 60);
      expect(repo.rows('redemptions').single['status'], 'confirmed');
      expect(
        repo.rows('ledger').where((row) => row['actual'] == -25),
        hasLength(1),
      );

      final another = (await command(parent, '/v1/subjects', {
        'name': 'Проверочное чтение',
      }))['id'];
      await command(parent, '/v1/grades', {
        'subject_id': another,
        'date': today,
        'grade': 2,
      });
      await repo.sync();
      await open();
      await approve();
      await stage('stale-prompt');
      await repo.logout(remote: false);
      await repo.login(endpoint, 'quality104-other', password);
      await finished(5);
      expect(errors.single, isA<ApiFailure>());
      expect(repo.snapshot!['balance']['total'], 60);
      expect(
        repo.rows('penalties').where((p) => p['status'] == 'pending'),
        hasLength(1),
      );
      expect(
        repo.rows('ledger').where((row) => (row['actual'] as num) < 0),
        hasLength(2),
      );
      expect(await repo.pending(), isEmpty);
      await open();
      await repo.logout(remote: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Семейный доступ изменился'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Подтвердить'), findsNothing);
      await stage('stale-blocked');
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();

      await File('${support.path}/mykids-quality104-proof.json').writeAsString(
        jsonEncode({
          'actual_android': true,
          'actual_backend_http': true,
          'actual_android_device_credentials': true,
          'missing_pin_explained': true,
          'native_cancellation_no_debit': true,
          'native_penalty_one_debit': true,
          'native_payout_one_debit': true,
          'session_change_stops_native_prompt': true,
          'session_change_hides_terms': true,
          'actual_private_queue_empty': true,
          'synthetic_only': true,
          'physical_phone': false,
        }),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
      transport.close();
    }
  });
}
