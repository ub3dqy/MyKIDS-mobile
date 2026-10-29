import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/family_screen.dart';

import 'support/messenger_fixture.dart';

class PendingFirstChat extends MessengerFixture {
  final queued = <Map<String, Object?>>[
    {
      'path': '/v1/rooms/private/messages',
      'method': 'POST',
      'state': 'pending',
    },
  ];

  @override
  Future<List<Map<String, Object?>>> pending() async =>
      queued.map((row) => Map<String, Object?>.from(row)).toList();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
  });
  for (final design in GameDesign.all) {
    testWidgets('${design.id}: first queued message keeps its chat reachable', (
      tester,
    ) async {
      final repo = PendingFirstChat();
      gameDesign.value = design;
      addTearDown(() {
        gameDesign.value = null;
        repo.client.close();
        repo.dispose();
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
      expect(find.text('Папа'), findsOneWidget);
      expect(find.text('Ждёт отправки'), findsOneWidget);
      repo.queued.single['state'] = 'failed';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Папа'), findsOneWidget);
      expect(find.text('Не отправлено'), findsOneWidget);
      repo.queued.clear();
      repo.online = false;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Папа'), findsOneWidget);
      repo.online = true;
      repo.queued.add({
        'path': '/v1/tasks/read/submissions',
        'method': 'POST',
        'state': 'pending',
      });
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Папа'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
