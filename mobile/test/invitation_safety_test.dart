import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/invitation_dialog.dart';
import 'package:mykids_family/settings_screen.dart';

import 'field_layout_test.dart' show mountFields, revealField;
import 'settings_safety_test.dart' show SettingsRepository;

class InviteRepository extends SettingsRepository {
  final requests = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function()? reply;
  int expiresIn = 86400;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) async {
    expect(path, '/v1/invites');
    expect(method, 'POST');
    requests.add({...?body});
    if (reply != null) return reply!();
    return {'token': 'a' * 43, 'expires_in': expiresIn};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late InviteRepository repo;
  late BackgroundServices background;
  late List<Object> errors;
  late List<String> copies;
  late Future<void> Function() copy;

  void invitationTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  setUp(() {
    repo = InviteRepository();
    background = BackgroundServices(repo);
    errors = [];
    copies = [];
    copy = () async {};
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copies.add((call.arguments as Map)['text'] as String);
        await copy();
      }
      return null;
    });
    messenger.setMockMethodCallHandler(nativeCalls, (call) async {
      if (call.method == 'copyInvitation') {
        copies.add((call.arguments as Map)['token'] as String);
        await copy();
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(nativeCalls, null);
    background.dispose();
    repo.client.close();
    repo.dispose();
  });

  Future<void> show(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await mountFields(
      tester,
      Scaffold(
        body: SettingsScreen(
          repository: repo,
          background: background,
          perform: (action) async {
            try {
              await action();
            } catch (error) {
              errors.add(error);
            }
          },
          onUpdates: () async {},
        ),
      ),
      scale: 1.5,
    );
  }

  Future<void> create(WidgetTester tester, {String role = 'child'}) async {
    final label = {
      'child': 'Подключить ребёнка',
      'parent': 'Подключить второго родителя',
      'relative': 'Подключить бабушку или дедушку',
    }[role]!;
    final button = find.widgetWithText(OutlinedButton, label);
    await revealField(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> pressCopy(WidgetTester tester) async {
    final button = find.text('Скопировать');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  void changeAccount() {
    repo.token = 'another-synthetic-invite-owner';
    repo.generation++;
    repo.notifyListeners();
  }

  invitationTest('late invite response is not shown after changing account', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    repo.reply = () => response.future;
    await show(tester);
    await create(tester);
    changeAccount();
    response.complete({'token': 'a' * 43, 'expires_in': 86400});
    await tester.pumpAndSettle();
    expect(find.byType(InvitationQr), findsNothing);
  });

  for (final change in ['account', 'role']) {
    invitationTest('open invite hides its secret after changing $change', (
      tester,
    ) async {
      await show(tester);
      await create(tester);
      expect(find.byType(InvitationQr), findsOneWidget);
      if (change == 'account') {
        changeAccount();
      } else {
        repo.snapshot!['user']['role'] = 'child';
        repo.notifyListeners();
      }
      await tester.pumpAndSettle();
      expect(find.byType(InvitationQr), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('Скопировать'), findsNothing);
    });
  }

  invitationTest('captured copy callback cannot copy after account changes', (
    tester,
  ) async {
    await show(tester);
    await create(tester);
    final callback = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Скопировать'))
        .onPressed!;
    changeAccount();
    callback();
    await tester.pumpAndSettle();
    expect(copies, isEmpty);
  });

  invitationTest(
    'changing account during copy never reports the old secret copied',
    (tester) async {
      final gate = Completer<void>();
      copy = () => gate.future;
      await show(tester);
      await create(tester);
      await pressCopy(tester);
      changeAccount();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Код скопирован'), findsNothing);
      expect(find.byType(InvitationQr), findsNothing);
    },
  );

  invitationTest('repeated creation callbacks request only one invitation', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    repo.reply = () => response.future;
    await show(tester);
    final button = find.widgetWithText(OutlinedButton, 'Подключить ребёнка');
    await revealField(tester, button);
    final callback = tester.widget<OutlinedButton>(button).onPressed!;
    callback();
    callback();
    await tester.pump();
    response.complete({'token': 'a' * 43, 'expires_in': 86400});
    await tester.pumpAndSettle();
    expect(repo.requests, hasLength(1));
    expect(find.byType(InvitationDialog, skipOffstage: false), findsOneWidget);
  });

  invitationTest('repeated copy callbacks send one clipboard request', (
    tester,
  ) async {
    final gate = Completer<void>();
    copy = () => gate.future;
    await show(tester);
    await create(tester);
    final callback = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Скопировать'))
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(copies, ['a' * 43]);
  });

  invitationTest(
    'clipboard failure stays in the dialog with a readable retry',
    (tester) async {
      copy = () async => throw PlatformException(code: 'unavailable');
      await show(tester);
      await create(tester);
      await pressCopy(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Не удалось скопировать'), findsOneWidget);
      expect(find.text('Скопировать'), findsOneWidget);
      copy = () async {};
      await pressCopy(tester);
      expect(find.text('Код скопирован'), findsOneWidget);
    },
  );

  invitationTest('expired invitation hides QR and copy action', (tester) async {
    repo.expiresIn = 2;
    await show(tester);
    await create(tester);
    expect(find.byType(InvitationQr), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(InvitationQr), findsNothing);
    expect(find.text('Скопировать'), findsNothing);
    expect(find.textContaining('Срок приглашения истёк'), findsOneWidget);
  });

  invitationTest(
    'offline creation is disabled, existing valid invitation remains usable offline',
    (tester) async {
      await show(tester);
      repo.online = false;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      // Refresh the same settings widget as the main application does.
      await show(tester);
      final button = find.widgetWithText(OutlinedButton, 'Подключить ребёнка');
      await revealField(tester, button);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      repo.online = true;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      await create(tester);
      repo.online = false;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      await pressCopy(tester);
      expect(copies, ['a' * 43]);
    },
  );

  for (final role in ['child', 'parent', 'relative']) {
    invitationTest('fresh $role invitation copies the exact single-use token', (
      tester,
    ) async {
      await show(tester);
      await create(tester, role: role);
      expect(repo.requests, [
        {'role': role},
      ]);
      expect(find.byType(InvitationQr), findsOneWidget);
      expect(
        find.text(
          {
            'child': 'Для ребёнка',
            'parent': 'Для второго родителя',
            'relative': 'Для бабушки или дедушки',
          }[role]!,
        ),
        findsOneWidget,
      );
      await pressCopy(tester);
      expect(copies, ['a' * 43]);
      expect(find.text('Код скопирован'), findsOneWidget);
      expect(errors, isEmpty);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
    });
  }

  for (final change in ['endpoint', 'generation']) {
    invitationTest('late invitation cannot cross changed $change', (
      tester,
    ) async {
      final response = Completer<Map<String, dynamic>>();
      repo.reply = () => response.future;
      await show(tester);
      await create(tester);
      if (change == 'endpoint') {
        repo.endpoint = 'https://another-synthetic-family.invalid';
      } else {
        repo.generation++;
      }
      repo.notifyListeners();
      response.complete({'token': 'a' * 43, 'expires_in': 86400});
      await tester.pumpAndSettle();
      expect(find.byType(InvitationQr), findsNothing);
    });
  }
  invitationTest('leaving settings suppresses a late invitation', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    repo.reply = () => response.future;
    await show(tester);
    await create(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    response.complete({'token': 'a' * 43, 'expires_in': 86400});
    await tester.pumpAndSettle();
    expect(find.byType(InvitationQr), findsNothing);
  });
  invitationTest('expired captured callback cannot copy the token', (
    tester,
  ) async {
    repo.expiresIn = 2;
    await show(tester);
    await create(tester);
    final callback = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Скопировать'))
        .onPressed!;
    await tester.pump(const Duration(seconds: 3));
    callback();
    await tester.pumpAndSettle();
    expect(copies, isEmpty);
  });
  invitationTest('closing an invitation twice preserves settings underneath', (
    tester,
  ) async {
    await show(tester);
    await create(tester);
    final callback = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Закрыть'))
        .onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await create(tester, role: 'relative');
    expect(repo.requests, hasLength(2));
    expect(find.byType(InvitationQr), findsOneWidget);
  });
  invitationTest(
    'background hides the secret and valid same-owner resume restores it',
    (tester) async {
      await show(tester);
      await create(tester);
      final callback = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Скопировать'))
          .onPressed!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(InvitationQr), findsNothing);
      callback();
      await tester.pumpAndSettle();
      expect(copies, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(InvitationQr), findsOneWidget);
      await pressCopy(tester);
      expect(copies, ['a' * 43]);
    },
  );
  for (final duration in [0, -1, 86401, null, '2']) {
    invitationTest(
      'invalid server lifetime $duration never displays a secret',
      (tester) async {
        repo.reply = () async => {'token': 'a' * 43, 'expires_in': duration};
        await show(tester);
        await create(tester);
        expect(find.byType(InvitationQr), findsNothing);
        expect(errors, hasLength(1));
      },
    );
  }
  invitationTest('invalid returned token is never rendered or copied', (
    tester,
  ) async {
    repo.reply = () async => {'token': 'invalid', 'expires_in': 86400};
    await show(tester);
    await create(tester);
    expect(find.byType(InvitationQr), findsNothing);
    expect(copies, isEmpty);
    expect(errors, hasLength(1));
  });
}
