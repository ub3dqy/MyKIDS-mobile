import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/incoming_calls.dart';
import 'package:mykids_family/updates.dart';
import 'package:mykids_family/visuals.dart';

import '../test/support/messenger_fixture.dart';

class NoMessengerUpdates extends AppUpdates {
  @override
  Future<UpdateOffer?> check(Uri url, String role) async => null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android messenger layout, draft retry, history and native voice recording',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot(name);
      }

      for (final role in ['child', 'parent', 'relative']) {
        final repo = MessengerFixture(role: role);
        await tester.pumpWidget(
          MyKidsApp(
            repository: repo,
            createUpdates: NoMessengerUpdates.new,
            now: () => DateTime.utc(2026, 10, 12, 10),
          ),
        );
        await tester.runAsync(
          () => precacheFamilyArtwork(tester.element(find.byType(MyKidsApp))),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Семья'));
        await tester.pumpAndSettle();
        expect(find.byType(FamilyScreen), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture('messenger-$role-chats');
        await tester.tap(find.text('Звонки'));
        await tester.pumpAndSettle();
        await capture('messenger-$role-calls');
        await tester.tap(find.text('Чаты'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Вся семья'));
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsOneWidget);
        await capture('messenger-$role-conversation');
        if (role == 'child') {
          repo.failSend = true;
          await tester.enterText(find.byType(TextField), 'Скоро буду дома');
          await tester.pump();
          await tester.tap(find.byTooltip('Отправить'));
          await tester.pumpAndSettle();
          expect(
            find.text('Не удалось отправить. Попробуйте ещё раз.'),
            findsOneWidget,
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Скоро буду дома',
          );
          repo.failSend = false;
          await tester.tap(find.byTooltip('Отправить'));
          await tester.pumpAndSettle();
          expect(repo.sent, ['Скоро буду дома']);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Более ранние сообщения'),
            150,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.tap(find.text('Более ранние сообщения'));
          await tester.pumpAndSettle();
          expect(repo.earlierLoaded, true);
          await tester.tap(find.byTooltip('Голосовое'));
          await tester.pumpAndSettle();
          expect(find.text('Идёт запись…'), findsOneWidget);
          await capture('messenger-child-recording');
          await Future<void>.delayed(const Duration(seconds: 1));
          await tester.tap(find.byTooltip('Завершить запись'));
          await tester.pumpAndSettle();
          expect(repo.uploadedBytes, greaterThan(44));
          expect(find.text('Идёт запись…'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        repo.client.close();
        repo.dispose();
      }
      for (final video in [false, true]) {
        final repo = MessengerFixture();
        await tester.pumpWidget(
          MaterialApp(
            theme: familyTheme(false),
            home: Scaffold(
              backgroundColor: const Color(0xffeaf0f7),
              body: Center(
                child: IncomingCallDialog(
                  repository: repo,
                  call: {
                    'id': 'preview',
                    'caller_id': 'parent',
                    'video': video ? 1 : 0,
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Папа'), findsOneWidget);
        expect(find.text('Ответить'), findsOneWidget);
        await capture(
          video ? 'messenger-incoming-video' : 'messenger-incoming-audio',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        repo.client.close();
        repo.dispose();
      }
      binding.reportData = {
        ...?binding.reportData,
        'roles': ['child', 'parent', 'relative'],
        'draft_retry': true,
        'history': true,
        'native_recording_nonempty': true,
        'synthetic_only': true,
        'invitation_component_previews': true,
        'scope': 'Android emulator only; artificial chat data; recording upload simulated; incoming invitation images are isolated widget previews; actual invitation actions and media checked separately; no family accounts or physical phones.',
      };
    },
  );
}
