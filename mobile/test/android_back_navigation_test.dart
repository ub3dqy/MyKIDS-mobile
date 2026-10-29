import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_review.dart'
    show ReviewBackground, ReviewUpdates;
import 'package:mykids_family/design_review_control.dart';
import 'package:mykids_family/design_review_repository.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/role_screen.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final design in GameDesign.all) {
    for (final role in ['child', 'parent', 'relative']) {
      testWidgets(
        '${design.id}/$role: Android Back returns every tab to Today',
        (tester) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          gameDesign.value = design;
          final repo = DesignReviewRepository()..switchRole(role);
          final pages = ReviewPageSelection();
          final navigation = GlobalKey<NavigatorState>();
          var exits = 0;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'SystemNavigator.pop') exits++;
              return null;
            },
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await frames(tester);
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            );
            gameDesign.value = null;
            pages.dispose();
            repo.client.close();
            repo.dispose();
          });
          await tester.pumpWidget(
            MyKidsApp(
              repository: repo,
              pageSelection: pages,
              navigationKey: navigation,
              createBackground: ReviewBackground.new,
              createUpdates: ReviewUpdates.new,
            ),
          );
          await frames(tester);
          for (final page in [1, 2, if (role != 'relative') 3, 4, 5]) {
            pages.select(page);
            await frames(tester);
            expect(
              tester
                  .widget<GameNavigation>(find.byType(GameNavigation))
                  .selected,
              page,
            );
            // A dialog must close first, preserving the underlying selected tab.
            showDialog<void>(
              context: navigation.currentContext!,
              builder: (_) =>
                  const AlertDialog(content: Text('Проверка возврата')),
            );
            await frames(tester);
            await tester.binding.handlePopRoute();
            await frames(tester);
            expect(find.byType(AlertDialog), findsNothing);
            expect(
              tester
                  .widget<GameNavigation>(find.byType(GameNavigation))
                  .selected,
              page,
            );
            expect(exits, 0);
            await tester.binding.handlePopRoute();
            await frames(tester);
            expect(
              tester
                  .widget<GameNavigation>(find.byType(GameNavigation))
                  .selected,
              0,
              reason: 'Android Back from tab $page must return to Today',
            );
            expect(exits, 0);
          }
          // On Today the ordinary Android exit remains available.
          await tester.binding.handlePopRoute();
          await frames(tester);
          expect(exits, 1);
          expect(repo.signedIn, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await frames(tester);
        },
      );

      testWidgets(
        '${design.id}/$role: Android Back from login returns to roles',
        (tester) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          gameDesign.value = design;
          final repo = DesignReviewRepository();
          repo.token = null;
          repo.snapshot = null;
          repo.variant = role;
          final navigation = GlobalKey<NavigatorState>();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await frames(tester);
            gameDesign.value = null;
            repo.client.close();
            repo.dispose();
          });
          await tester.pumpWidget(
            MyKidsApp(
              repository: repo,
              navigationKey: navigation,
              createBackground: ReviewBackground.new,
              createUpdates: ReviewUpdates.new,
            ),
          );
          await frames(tester);
          expect(find.byType(LoginScreen), findsOneWidget);
          await tester.binding.handlePopRoute();
          await frames(tester);
          expect(find.byType(RoleScreen), findsOneWidget);
          expect(repo.variant, isEmpty);
          expect(repo.signedIn, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await frames(tester);
        },
      );
    }
  }
}
