import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/child_visuals.dart';
import 'package:mykids_family/visuals.dart';

Widget scene({bool reduce = false, bool enabled = true}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: TickerMode(
      enabled: enabled,
      child: const Scaffold(body: ChildMotion(celebrate: true)),
    ),
  ),
);
void main() {
  testWidgets(
    'authored frames animate, pause in background, resume, reduce motion',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(scene());
      Rect frame() =>
          tester.widget<RasterSprite>(find.byType(RasterSprite)).source;
      final initial = frame();
      await tester.pump(const Duration(milliseconds: 160));
      expect(frame(), isNot(initial));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final paused = frame();
      await tester.pump(const Duration(seconds: 2));
      expect(frame(), paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump(const Duration(milliseconds: 160));
      expect(frame(), isNot(paused));
      await tester.pumpWidget(scene(reduce: true));
      final reduced = frame();
      expect(reduced, const Rect.fromLTWH(2 / 3, .5, 1 / 3, .5));
      await tester.pump(const Duration(seconds: 2));
      expect(frame(), reduced);
      await tester.pumpWidget(scene(enabled: false));
      final hidden = frame();
      await tester.pump(const Duration(seconds: 2));
      expect(frame(), hidden);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
