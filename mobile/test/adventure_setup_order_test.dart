import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_model.dart';
import 'package:mykids_family/engagement/engagement_pages.dart';
import 'package:mykids_family/engagement/engagement_scope.dart';
import 'package:mykids_family/engagement/preview_controller.dart';

class ServerOrderedController extends PreviewEngagementController {
  ServerOrderedController()
    : super(EngagementReviewRepository(), save: (_) async {});
  @override
  List<PlayTask> get tasks =>
      [...super.tasks]..sort((a, b) => a.id.compareTo(b.id));
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
  });
  for (final design in GameDesign.all) {
    testWidgets(
      '${design.id}: route tasks keep approved order across server order and checkbox edits',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = ServerOrderedController();
        await c.switchRole('parent');
        gameDesign.value = design;
        addTearDown(() {
          gameDesign.value = null;
          c.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: design.theme(false),
            home: EngagementScope(
              controller: c,
              child: const AdventureSetupPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        List<String> visibleOrder() => tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .map((tile) => (tile.title! as Text).data!)
            .toList();
        const expected = [
          'Прочитать 10 страниц',
          'Собрать рюкзак',
          'Полить цветы',
          'Выбрать фильм',
        ];
        expect(visibleOrder(), expected);
        await tester.tap(
          find.widgetWithText(CheckboxListTile, 'Прочитать 10 страниц'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Выбрано 2 из 3'), findsOneWidget);
        expect(
          visibleOrder(),
          expected,
          reason: 'Rows do not jump while the parent edits the selection',
        );
        expect(c.state.adventureTaskIds, ['flowers', 'read', 'bag']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
