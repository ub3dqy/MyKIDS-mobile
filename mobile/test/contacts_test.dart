import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/visuals.dart';

import 'support/messenger_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        ),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          null,
        ),
  );

  Future<void> showContacts(
    WidgetTester tester,
    ContactsFixture repo, {
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: familyTheme(repo.role == 'child'),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: FamilyScreen(
              repository: repo,
              perform: (action) async {
                await action();
              },
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Контакты'));
    await tester.tap(find.text('Контакты'));
    await tester.pumpAndSettle();
  }

  for (final actor in ['papa', 'stepa', 'grandma1']) {
    testWidgets('all six other family contacts open private chats for $actor', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = ContactsFixture(actorId: actor);
      await showContacts(tester, repo, textScale: 2);
      expect(find.byKey(ValueKey('contact-$actor')), findsNothing);
      final target = actor == 'papa' ? 'mama' : 'papa';
      final name = target == 'mama' ? 'Мама' : 'Папа';
      await tester.ensureVisible(find.byKey(ValueKey('contact-$target')));
      await tester.tap(find.byKey(ValueKey('contact-$target')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text(name), findsOneWidget);
      expect(find.byTooltip('Аудиозвонок'), findsOneWidget);
      expect(find.byTooltip('Видеозвонок'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      repo.client.close();
      repo.dispose();
    });
  }

  testWidgets(
    'contacts refresh after adding a member; search and deactivation update the list',
    (tester) async {
      final repo = ContactsFixture();
      (repo.snapshot!['members'] as List).removeWhere(
        (m) => m['id'] == 'grandpa2',
      );
      (repo.snapshot!['rooms'] as List).removeWhere(
        (r) => (r['contact'] as Map?)?['id'] == 'grandpa2',
      );
      await showContacts(tester, repo);
      await tester.enterText(
        find.byKey(const ValueKey('contact-search')),
        'Дедушка 2',
      );
      await tester.pump();
      expect(find.text('Контакты не найдены'), findsOneWidget);
      repo.addContact({
        'id': 'grandpa2',
        'name': 'Дедушка 2',
        'role': 'relative',
        'active': 1,
      });
      await tester.pump();
      expect(find.byKey(const ValueKey('contact-grandpa2')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('contact-grandpa2')),
          matching: find.text('Дедушка 2'),
        ),
        findsOneWidget,
      );
      repo.deactivateContact('grandpa2');
      await tester.pump();
      expect(find.byKey(const ValueKey('contact-grandpa2')), findsNothing);
      expect(find.text('Контакты не найдены'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    },
  );

  testWidgets(
    'shared family conversation supports messages and has no call buttons',
    (tester) async {
      final repo = ContactsFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(false),
          home: ChatScreen(
            repository: repo,
            room: repo.rows('rooms').firstWhere((r) => r['kind'] == 'family'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Вся семья'), findsOneWidget);
      expect(find.byTooltip('Аудиозвонок'), findsNothing);
      expect(find.byTooltip('Видеозвонок'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Привет всей семье');
      await tester.pump();
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();
      expect(repo.sent, ['Привет всей семье']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      repo.client.close();
      repo.dispose();
    },
  );
}
