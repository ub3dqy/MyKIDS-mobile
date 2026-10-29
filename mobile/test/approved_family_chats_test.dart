import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/messenger_widgets.dart';

import 'support/messenger_fixture.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
  });
  for (final design in GameDesign.all) {
    testWidgets(
      '${design.id}: approved chats, contacts, call history and new message',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final repo = MessengerFixture();
          gameDesign.value = design;
          addTearDown(() {
            gameDesign.value = null;
            repo.client.close();
            repo.dispose();
          });
          (repo.snapshot!['calls'] as List).add({
            'id': 'private-call',
            'room_id': 'private',
            'caller_id': 'child',
            'status': 'ended',
            'member_status': 'left',
            'video': 0,
            'created_at': '2026-10-12T09:40:00Z',
          });
          await tester.pumpWidget(
            MaterialApp(
              theme: design.theme(true),
              home: Scaffold(
                body: FamilyScreen(
                  repository: repo,
                  perform: (action) async {
                    await action();
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Наша семья'), findsOneWidget);
          expect(find.text('Вся семья'), findsNothing);
          expect(find.text('Папа'), findsNothing);
          await tester.tap(find.text('Контакты'));
          await tester.pumpAndSettle();
          expect(find.text('Папа'), findsOneWidget);
          await tester.tap(find.text('Звонки'));
          await tester.pumpAndSettle();
          expect(
            find.text('Папа'),
            findsOneWidget,
            reason: 'Calls still resolve rooms hidden from the chat list',
          );
          expect(
            tester
                .widgetList<FamilyAvatar>(find.byType(FamilyAvatar))
                .any((a) => a.group),
            isTrue,
          );
          await tester.tap(find.text('Чаты'));
          await tester.pumpAndSettle();
          final room = (repo.snapshot!['rooms'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((r) => r['kind'] == 'private');
          room['last_message'] = {
            'sender_id': 'parent',
            'text': 'Новая весточка',
            'created_at': '2026-10-12T10:05:00Z',
          };
          room['unread_count'] = 1;
          // Replace the summary in the fixture snapshot, as an incoming sync does.
          repo.notifyListeners();
          await tester.pumpAndSettle();
          expect(find.text('Папа'), findsOneWidget);
          expect(find.text('Папа: Новая весточка'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp(r'Непрочитанных сообщений: 1')),
            findsOneWidget,
          );
          room.remove('last_message');
          room['unread_count'] = 0;
          repo.notifyListeners();
          await tester.pumpAndSettle();
          expect(
            find.text('Папа'),
            findsOneWidget,
            reason: 'Old caches without summaries remain usable',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
