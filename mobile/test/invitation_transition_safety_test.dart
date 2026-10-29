import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/invitation_dialog.dart';

import 'invitation_safety_test.dart' show InviteRepository;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InviteRepository repo;
  late ValueNotifier<InviteRepository?> selection;
  late List<String> copies;
  late List<Object> failures;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    repo = InviteRepository();
    selection = ValueNotifier(repo);
    copies = [];
    failures = [];
    messenger.setMockMethodCallHandler(nativeCalls, (call) async {
      if (call.method == 'copyInvitation') {
        copies.add((call.arguments as Map)['token'] as String);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copies.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      selection.dispose();
      repo.client.close();
      repo.dispose();
      messenger.setMockMethodCallHandler(nativeCalls, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<InviteRepository?>(
            valueListenable: selection,
            builder: (_, value, _) => value == null
                ? const Text('Другой раздел')
                : FamilyInvitations(
                    repository: value,
                    perform: (action) async {
                      try {
                        await action();
                      } catch (error) {
                        failures.add(error);
                      }
                    },
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Подключить ребёнка'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'pending invitation never revives after temporary parent access revocation',
    (tester) async {
      final reply = Completer<Map<String, dynamic>>();
      repo.reply = () => reply.future;
      await mount(tester);
      await open(tester);
      repo.snapshot!['user']['role'] = 'child';
      repo.notifyListeners();
      repo.snapshot!['user']['role'] = 'parent';
      repo.notifyListeners();
      reply.complete({'token': 'a' * 43, 'expires_in': 86400});
      await tester.pumpAndSettle();
      expect(find.byType(InvitationQr), findsNothing);
      expect(copies, isEmpty);
    },
  );

  for (final replace in [false, true]) {
    testWidgets(
      'invitation masks old secret when originating widget changes: replace=$replace',
      (tester) async {
        await mount(tester);
        await open(tester);
        expect(find.byType(InvitationQr), findsOneWidget);
        final replacement = replace ? InviteRepository() : null;
        if (replacement != null) {
          addTearDown(() {
            replacement.client.close();
            replacement.dispose();
          });
        }
        selection.value = replacement;
        await tester.pumpAndSettle();
        expect(find.byType(InvitationQr), findsNothing);
        expect(find.text('Скопировать'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final close in [false, true]) {
    testWidgets(
      'covered invitation ignores captured ${close ? 'close' : 'copy'} callback',
      (tester) async {
        await mount(tester);
        await open(tester);
        final callback = tester
            .widget<TextButton>(
              find.widgetWithText(
                TextButton,
                close ? 'Закрыть' : 'Скопировать',
              ),
            )
            .onPressed!;
        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('Важный открытый экран')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        callback();
        await tester.pumpAndSettle();
        expect(find.text('Важный открытый экран'), findsOneWidget);
        expect(copies, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'invitation creation remains single until the closing animation ends',
    (tester) async {
      await mount(tester);
      final create = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Подключить ребёнка'),
          )
          .onPressed!;
      create();
      await tester.pumpAndSettle();
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Закрыть'))
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 40));
      create();
      await tester.pump(const Duration(milliseconds: 40));
      expect(repo.requests, hasLength(1));
      await tester.pumpAndSettle();
      create();
      await tester.pumpAndSettle();
      expect(repo.requests, hasLength(2));
    },
  );
}
