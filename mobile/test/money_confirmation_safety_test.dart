import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';

import 'activity_lists_test.dart' show ActivityFixture;
import 'field_layout_test.dart' show mountFields, revealField;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/local_auth');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final payout in [false, true]) {
    group(payout ? 'payout' : 'penalty', () {
      late ActivityFixture repo;
      late List<Object> failures;
      late int authentications;
      late int stops;
      late Future<bool> Function() authenticate;

      setUp(() {
        repo = ActivityFixture()..token = 'synthetic-money-owner';
        repo.snapshot!['rewards'] = [];
        repo.snapshot!['redemptions'] = payout
            ? [
                {
                  'id': 'request',
                  'title': 'Проверочная выдача',
                  'amount': 25,
                  'status': 'claimed',
                  'claimed_by': 'dad',
                },
              ]
            : [];
        if (payout) repo.snapshot!['penalties'] = [];
        failures = [];
        authentications = 0;
        stops = 0;
        authenticate = () async => true;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'stopAuthentication') {
            stops++;
            return true;
          }
          expect(call.method, 'authenticate');
          authentications++;
          return authenticate();
        });
      });
      tearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        repo.client.close();
        repo.dispose();
      });

      Future<void> perform(
        Future<Map<String, dynamic>> Function() action,
      ) async {
        try {
          await action();
        } catch (error) {
          failures.add(error);
        }
      }

      Future<void> open(WidgetTester tester) async {
        await mountFields(
          tester,
          Scaffold(
            body: MoneyScreen(repository: repo, perform: perform),
          ),
          scale: 1.3,
        );
        if (payout) {
          await revealField(tester, find.text('Проверочная выдача · 25'));
          await tester.tap(find.text('Проверочная выдача · 25'));
          await tester.pumpAndSettle();
        }
        final button = find.text(
          payout ? 'Уже выдал — подтвердить' : 'Применить',
        );
        await revealField(tester, button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(authentications, 0);
      }

      Future<void> confirm(WidgetTester tester) async {
        final button = find.widgetWithText(FilledButton, 'Подтвердить');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      void changeSession() {
        repo.token = 'another-synthetic-money-owner';
        repo.generation++;
        repo.notifyListeners();
      }

      void changeDecision() {
        final record =
            (repo.snapshot![payout ? 'redemptions' : 'penalties'] as List)
                    .single
                as Map;
        record[payout ? 'claimed_by' : 'status'] = payout ? 'mom' : 'waived';
        repo.notifyListeners();
      }

      for (final approve in [false, true]) {
        testWidgets(
          'money $payout: retained ${approve ? 'approval' : 'cancel'} leaves a covering screen open',
          (tester) async {
            await open(tester);
            final dialog = tester.element(find.byType(AlertDialog));
            final callback = approve
                ? tester
                      .widget<FilledButton>(
                        find.widgetWithText(FilledButton, 'Подтвердить'),
                      )
                      .onPressed!
                : tester
                      .widget<TextButton>(
                        find.widgetWithText(TextButton, 'Отмена'),
                      )
                      .onPressed!;
            final navigator = Navigator.of(dialog);
            unawaited(
              navigator.push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) =>
                      const Scaffold(body: Text('Экран поверх подтверждения')),
                ),
              ),
            );
            await tester.pumpAndSettle();
            callback();
            await tester.pumpAndSettle();
            expect(find.text('Экран поверх подтверждения'), findsOneWidget);
            expect(authentications, 0);
            expect(repo.changes, isEmpty);
            navigator.pop(false);
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(failures, isEmpty);
          },
        );
      }

      testWidgets(
        'money $payout: retained approval cannot close an obsolete consent dialog',
        (tester) async {
          await open(tester);
          final approve = tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Подтвердить'),
              )
              .onPressed!;
          changeDecision();
          await tester.pumpAndSettle();
          approve();
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('Подтверждение недоступно'), findsOneWidget);
          expect(authentications, 0);
          expect(repo.changes, isEmpty);
          await tester.tap(find.widgetWithText(TextButton, 'Закрыть'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        },
      );

      testWidgets('money $payout: current consent can be cancelled', (
        tester,
      ) async {
        await open(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(authentications, 0);
        expect(repo.changes, isEmpty);
        expect(failures, isEmpty);
      });

      for (final account in [false, true]) {
        testWidgets(
          'money $payout: changed ${account ? 'account' : 'decision'} invalidates the open dialog',
          (tester) async {
            await open(tester);
            account ? changeSession() : changeDecision();
            await tester.pumpAndSettle();
            expect(
              find.widgetWithText(FilledButton, 'Подтвердить'),
              findsNothing,
            );
            if (account) {
              expect(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.textContaining(
                    payout ? 'Проверочная выдача' : 'Спишется вся сумма',
                  ),
                ),
                findsNothing,
              );
            }
            await tester.tap(find.text('Закрыть'));
            await tester.pumpAndSettle();
            expect(authentications, 0);
            expect(repo.changes, isEmpty);
          },
        );

        testWidgets(
          'money $payout: late device approval cannot cross a changed ${account ? 'account' : 'decision'}',
          (tester) async {
            final answer = Completer<bool>();
            authenticate = () => answer.future;
            await open(tester);
            await confirm(tester);
            expect(authentications, 1);
            account ? changeSession() : changeDecision();
            answer.complete(true);
            await tester.pumpAndSettle();
            expect(repo.changes, isEmpty);
          },
        );
      }

      testWidgets(
        'money $payout: repeated callbacks keep one dialog and one device prompt',
        (tester) async {
          final answer = Completer<bool>();
          authenticate = () => answer.future;
          await open(tester);
          final action = tester
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  payout ? 'Уже выдал — подтвердить' : 'Применить',
                ),
              )
              .onPressed!;
          action();
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          final approve = tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Подтвердить'),
              )
              .onPressed!;
          approve();
          approve();
          await tester.pumpAndSettle();
          action();
          await tester.pumpAndSettle();
          expect(authentications, 1);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(MoneyScreen), findsOneWidget);
          answer.complete(true);
          await tester.pumpAndSettle();
          expect(repo.changes, hasLength(1));
          expect(failures, isEmpty);
        },
      );

      for (final field in ['amount', 'generation', 'endpoint']) {
        testWidgets(
          'money $payout: changing $field invalidates the device result',
          (tester) async {
            final answer = Completer<bool>();
            authenticate = () => answer.future;
            await open(tester);
            await confirm(tester);
            if (field == 'amount') {
              final record =
                  (repo.snapshot![payout ? 'redemptions' : 'penalties'] as List)
                          .single
                      as Map;
              record['amount'] = (record['amount'] as int) + 1;
            } else if (field == 'generation') {
              repo.generation++;
            } else {
              repo.endpoint = 'https://another-synthetic-family.invalid';
            }
            repo.notifyListeners();
            await tester.pumpAndSettle();
            expect(stops, 1);
            answer.complete(true);
            await tester.pumpAndSettle();
            expect(repo.changes, isEmpty);
          },
        );
      }

      testWidgets(
        'money $payout: restored connection requires reopening consent',
        (tester) async {
          final answer = Completer<bool>();
          authenticate = () => answer.future;
          await open(tester);
          await confirm(tester);
          repo.online = false;
          repo.notifyListeners();
          await tester.pumpAndSettle();
          expect(stops, 1);
          repo.online = true;
          repo.notifyListeners();
          answer.complete(true);
          await tester.pumpAndSettle();
          expect(repo.changes, isEmpty);
        },
      );

      testWidgets(
        'money $payout: leaving the wallet blocks late device approval',
        (tester) async {
          final answer = Completer<bool>();
          authenticate = () => answer.future;
          await open(tester);
          await confirm(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          answer.complete(true);
          await tester.pumpAndSettle();
          expect(repo.changes, isEmpty);
        },
      );

      testWidgets(
        'money $payout: offline dialog does not request device authentication',
        (tester) async {
          await open(tester);
          repo.online = false;
          repo.notifyListeners();
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(FilledButton, 'Подтвердить'),
            findsNothing,
          );
          expect(find.textContaining('подключения'), findsOneWidget);
          await tester.tap(find.text('Закрыть'));
          await tester.pumpAndSettle();
          expect(authentications, 0);
          expect(repo.changes, isEmpty);
        },
      );

      testWidgets(
        'money $payout: device error explains the device, not the server',
        (tester) async {
          authenticate = () async =>
              throw PlatformException(code: 'NotAvailable');
          await open(tester);
          await confirm(tester);
          expect(repo.changes, isEmpty);
          expect(failures, hasLength(1));
          expect(failures.single, isA<ApiFailure>());
          expect(failures.single.toString(), contains('устройств'));
        },
      );
      testWidgets(
        'fresh money $payout confirmation sends one action after device approval',
        (tester) async {
          await open(tester);
          await confirm(tester);
          expect(authentications, 1);
          expect(repo.changes, [
            payout
                ? '/v1/redemptions/request/actions'
                : '/v1/penalties/fine/approve',
          ]);
          expect(failures, isEmpty);
        },
      );
      testWidgets(
        'cancelled device approval for money $payout sends no action',
        (tester) async {
          authenticate = () async => false;
          await open(tester);
          await confirm(tester);
          expect(repo.changes, isEmpty);
          expect(failures.single, isA<ApiFailure>());
          expect(failures.single.toString(), contains('отменено'));
        },
      );
    });
  }
}
