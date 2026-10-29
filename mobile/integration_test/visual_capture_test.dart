import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture real Android family screens with synthetic accounts', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    for (final entry in const {
      'child': 'testkid',
      'parent': 'testpapa',
      'relative': 'testgrandma',
    }.entries) {
      const selectedRole = String.fromEnvironment(
        'CAPTURE_ROLE',
        defaultValue: 'all',
      );
      if (selectedRole != 'all' && entry.key != selectedRole) continue;
      final repo = FamilyRepository();
      await repo.initialize(entry.key);
      await repo.login(
        'http://10.0.2.2:8765',
        entry.value,
        'emulator-only-12345',
      );
      await tester.pumpWidget(MyKidsApp(repository: repo));
      await tester.runAsync(
        () => precacheFamilyArtwork(tester.element(find.byType(TodayScreen))),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 20; attempt++) {
        final ready = find.descendant(
          of: find.byType(RasterSprite),
          matching: find.byType(CustomPaint),
        );
        if (ready.evaluate().length ==
            find.byType(RasterSprite).evaluate().length) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      expect(
        find
            .descendant(
              of: find.byType(RasterSprite),
              matching: find.byType(CustomPaint),
            )
            .evaluate()
            .length,
        find.byType(RasterSprite).evaluate().length,
      );
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .every((image) => image.image != null),
        true,
      );
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('${entry.key}-today');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await repo.logout();
      await repo.db!.close();
      repo.client.close();
      repo.dispose();
    }
    expect(Platform.isAndroid, true);
  });
}
