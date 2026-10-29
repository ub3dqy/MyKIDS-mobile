import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/calendar_action_safety_test.dart' as calendar;
import '../test/field_layout_test.dart' show revealField;

void main() {
  testWidgets(
    'a fast save uses the time just accepted before the dialog finishes fading',
    (tester) async {
      final repo = calendar.CalendarActionFixture();
      await calendar.mountCalendar(tester, repo);
      await calendar.openEditor(tester);
      final save = find.byKey(const ValueKey('event-save'));
      await revealField(tester, find.byKey(const ValueKey('event-start')));
      await tester.tap(find.byKey(const ValueKey('event-start')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('time-minute')), '30');
      await tester.tap(find.widgetWithText(TextButton, 'Готово'));
      // Flush the accepted decision without advancing the closing animation.
      await tester.pump();
      if (save.hitTestable().evaluate().isEmpty) {
        await tester.pumpAndSettle();
      }
      await tester.tap(save.hitTestable());
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
      expect((repo.writes.single['body'] as Map)['start'], '12:30');
    },
  );
}
