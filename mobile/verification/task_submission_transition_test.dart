import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../test/submission_photos_test.dart' show PhotoFixture;
import '../test/task_submission_safety_test.dart' show openSubmission;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  for (final action in ['Отмена', 'Отправить на проверку']) {
    testWidgets('normal $action keeps its content during the exit transition', (
      tester,
    ) async {
      final repo = PhotoFixture(minimum: 0);
      await openSubmission(tester, repo);
      await tester.tap(find.text(action));
      // Inspect the outgoing frame, before the route has disappeared.
      await tester.pump();
      expect(find.text('Нужно открыть окно заново'), findsNothing);
      expect(find.text('Отправить результат'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });
  }
}
