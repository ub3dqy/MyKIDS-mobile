import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/call_permissions.dart';
import 'package:mykids_family/design_review.dart'
    show ReviewBackground, ReviewUpdates;
import 'package:mykids_family/design_review_control.dart';
import 'package:mykids_family/design_review_repository.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/main.dart';

class MissingCallPermissions extends ReviewBackground {
  MissingCallPermissions(super.repository) {
    callsMicrophoneReady = false;
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
  });
  for (final design in GameDesign.all) {
    for (final role in ['child', 'parent', 'relative']) {
      testWidgets(
        '${design.id}/$role: setup stays in settings, routes keep approved text scale',
        (tester) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final repo = DesignReviewRepository()..switchRole(role);
          final pages = ReviewPageSelection();
          final navigation = GlobalKey<NavigatorState>();
          gameDesign.value = design;
          addTearDown(() {
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
              createBackground: MissingCallPermissions.new,
              createUpdates: ReviewUpdates.new,
            ),
          );
          await frames(tester);
          for (final page in [0, 1, 2, if (role != 'relative') 3, 4]) {
            pages.select(page);
            await frames(tester);
            expect(find.byType(CallPermissionNotice), findsNothing);
            final context = tester.element(find.byType(Scaffold).first);
            final scaler = MediaQuery.textScalerOf(context);
            expect(scaler, TextScaler.linear(1.5));
            expect(scaler.scale(40), 60);
            expect(tester.takeException(), isNull);
          }
          BuildContext? pushed;
          navigation.currentState!.push<void>(
            MaterialPageRoute(
              builder: (context) {
                pushed = context;
                return const Scaffold(body: Text('Проверка масштаба'));
              },
            ),
          );
          await frames(tester);
          expect(MediaQuery.textScalerOf(pushed!), TextScaler.linear(1.5));
          navigation.currentState!.pop();
          await frames(tester);
          pages.select(5);
          await frames(tester);
          if (role == 'child') {
            await tester.ensureVisible(find.text('Настройки телефона'));
            await tester.tap(find.text('Настройки телефона'));
            await frames(tester);
          }
          expect(find.byType(CallPermissionNotice), findsOneWidget);
          expect(find.text('Настроить звонки'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await frames(tester);
        },
      );
    }
  }
}
