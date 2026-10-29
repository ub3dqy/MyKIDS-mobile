import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/call_view.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/messenger_widgets.dart';
import 'package:mykids_family/updates.dart';
import 'package:mykids_family/visuals.dart';

import '../test/support/messenger_fixture.dart';

class NoContactsUpdates extends AppUpdates {
  @override
  Future<UpdateOffer?> check(Uri url, String role) async => null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android family contacts, direct chats, shared chat and four-person call layout',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        // Give the Android rasterizer time to upload glyphs after role/theme changes.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 350)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await binding.takeScreenshot(name);
      }

      for (final actor in ['papa', 'stepa', 'grandma1']) {
        final repo = ContactsFixture(actorId: actor);
        await tester.pumpWidget(
          MyKidsApp(
            repository: repo,
            createUpdates: NoContactsUpdates.new,
            now: () => DateTime.utc(2026, 10, 12, 10),
          ),
        );
        await tester.runAsync(
          () => precacheFamilyArtwork(tester.element(find.byType(MyKidsApp))),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Семья'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Контакты'));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('contact-$actor')), findsNothing);
        await capture('contacts-$actor-list');
        final peer = actor == 'papa' ? 'mama' : 'papa';
        await tester.ensureVisible(find.byKey(ValueKey('contact-$peer')));
        await tester.tap(find.byKey(ValueKey('contact-$peer')));
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.byTooltip('Аудиозвонок'), findsOneWidget);
        expect(find.byTooltip('Видеозвонок'), findsOneWidget);
        await capture('contacts-$actor-private-chat');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Чаты'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Вся семья'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Аудиозвонок'), findsNothing);
        expect(find.byTooltip('Видеозвонок'), findsNothing);
        if (actor == 'papa') await capture('contacts-shared-chat');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        repo.client.close();
        repo.dispose();
      }
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyCallView(
            title: 'Семейная конференция',
            status: 'Соединение установлено · 4 из 4',
            people: const [
              CallPerson(name: 'Папа', local: true),
              CallPerson(name: 'Мама'),
              CallPerson(name: 'Бабушка 1'),
              CallPerson(name: 'Стёпа'),
            ],
            controls: [
              CallControl(label: 'Микрофон', icon: Icons.mic, onPressed: () {}),
              CallControl(
                label: 'Камера',
                icon: Icons.videocam,
                onPressed: () {},
              ),
              const CallControl(
                label: 'Пригласить',
                icon: Icons.person_add_alt_1,
              ),
            ],
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture('contacts-four-person-call-component');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'roles_checked': 3,
        'contacts_exclude_self': true,
        'personal_chat_has_audio_and_video': true,
        'shared_chat_has_no_call_buttons': true,
        'four_person_call_component_preview': true,
        'synthetic_only': true,
        'scope': 'Owned Android 16 emulator; artificial contacts; conference image is a presentation component preview, actual four-person media is checked separately with Python peers',
      });
    },
  );
}
