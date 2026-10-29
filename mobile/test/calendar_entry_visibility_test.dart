import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/morning.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  for (final kind in ['school', 'extra', 'task']) {
    testWidgets('$kind: keep the first pose while its dialog enters', (
      tester,
    ) async {
      final strip = kind == 'school' ? 'book' : kind;
      await tester.runAsync(
        () => precacheRasterArtwork(['assets/generated/calendar-$strip.png']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showGeneralDialog<void>(
                  context: context,
                  transitionDuration: const Duration(milliseconds: 960),
                  pageBuilder: (_, animation, secondary) =>
                      Center(child: CalendarMotion(kind: kind)),
                ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();
      Rect pose() =>
          tester.widget<RasterSprite>(find.byType(RasterSprite)).source;
      final first = pose();
      await tester.pump(const Duration(milliseconds: 640));
      expect(pose(), first, reason: 'Entering is not a visible gesture.');
      await tester.pump(const Duration(milliseconds: 320));
      AnimationStatus entryStatus() =>
          ModalRoute.of(tester.element(find.byType(CalendarMotion)))!
              .animation!
              .status;
      for (
        var attempt = 0;
        attempt < 20 && entryStatus() != AnimationStatus.completed;
        attempt++
      ) {
        expect(pose(), first);
        await tester.pump(const Duration(milliseconds: 80));
      }
      await tester.pump();
      expect(entryStatus(), AnimationStatus.completed);
      expect(pose(), first, reason: 'First pose must paint after entry ends.');
      for (final frame in [1, 2, 3]) {
        await tester.pump(const Duration(milliseconds: 320));
        const extraEdges = [0.0, 384.0, 730.0, 1190.0, 1536.0];
        final left = kind == 'extra' ? extraEdges[frame] / 1536 : frame / 4;
        expect(pose().left, left);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closing an entering helper cancels its pending gesture', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    final opened = showGeneralDialog<void>(
      context: navigator.currentContext!,
      transitionDuration: const Duration(seconds: 1),
      pageBuilder: (_, animation, secondary) =>
          const Center(child: CalendarMotion(kind: 'school')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await opened;
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CalendarMotion), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
