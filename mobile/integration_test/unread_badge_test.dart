import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/family_screen.dart';

import '../test/field_layout_test.dart' show mountFields;
import '../test/unread_badge_test.dart' show ReadFixture, settleReads;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android clears viewed photo badges and preserves new unread messages',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      final results = <String, dynamic>{
        'synthetic_only': true,
        'physical_devices_tested': false,
      };
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        await binding.takeScreenshot('unread-$name');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        expect(tester.takeException(), isNull);
      }

      for (final role in ['parent', 'child']) {
        final repo = ReadFixture(
          actorRole: role,
          kind: role == 'child' ? 'family' : 'private',
        );
        try {
          await mountFields(
            tester,
            Scaffold(
              appBar: AppBar(
                title: Text(
                  role == 'child' ? 'MyKIDS · Ребёнок' : 'MyKIDS · Папа',
                ),
              ),
              body: FamilyScreen(
                key: ObjectKey(repo),
                repository: repo,
                perform: (_) async =>
                    fail('Reading must not alter tasks or coins'),
              ),
            ),
            child: role == 'child',
            scale: 1.2,
            screenSize: null,
          );
          expect(
            find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 2')),
            findsOneWidget,
          );
          if (role == 'parent') await capture('parent-before');
          await tester.tap(
            find.text(role == 'parent' ? 'Степан' : 'Вся семья'),
          );
          await settleReads(tester);
          expect(repo.unread, 0);
          expect(repo.readRequests.map((r) => r['id']).toSet(), {
            'incoming-0',
            'incoming-1',
          });
          expect(find.byTooltip('Отметить прочитанным'), findsNothing);
          await tester.tap(find.byTooltip('Назад'));
          await tester.pumpAndSettle();
          expect(
            find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 2')),
            findsNothing,
          );
          await capture('$role-after');
          repo.addIncoming('new-$role');
          await tester.pumpAndSettle();
          expect(
            find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 1')),
            findsOneWidget,
          );
          expect(repo.readRequests.length, 2);
          if (role == 'parent') await capture('parent-new');
          results[role] = {
            'viewed_photos_read_automatically': true,
            'badge_cleared_on_return': true,
            'new_messages_stay_unread': true,
            'unrelated_room_unchanged':
                repo.rows('rooms').last['unread_count'] == 7,
          };
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          repo.client.close();
          repo.dispose();
        }
      }
      binding.reportData = {...?binding.reportData, ...results};
    },
  );
}
