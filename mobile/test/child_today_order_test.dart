import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/visuals.dart';

class TodayFixture extends FamilyRepository {
  TodayFixture() {
    variant = 'child';
    online = true;
    snapshot = {
      'user': {'id': 'fixture-child', 'role': 'child', 'name': 'Проверка'},
      'family': {
        'timezone': 'Europe/Moscow',
        'day_start': '07:00',
        'day_end': '22:00',
      },
      'server_time': '2026-10-12T08:00:00Z',
      'balance': {'available': 123456789},
      'schedules': [],
      'schedule_exceptions': [],
      'ledger': [],
      'tasks': [],
    };
  }
  @override
  Future<List<Map<String, Object?>>> pending() async => [];
}

void main() {
  testWidgets(
    'day comes first, tasks second, coin card is absent and header balance opens coins',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      final repo = TodayFixture();
      var page = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(true),
          home: StatefulBuilder(
            builder: (context, setState) => MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 900),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                appBar: AppBar(
                  title: const FamilyLogo(width: 96),
                  actions: [
                    FamilyCoinButton(
                      amount: 123456789,
                      online: true,
                      onPressed: () => setState(() => page = 3),
                    ),
                  ],
                ),
                body: page == 3
                    ? const Text('Открыты монеты')
                    : ChildToday(repository: repo, openPage: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Твой день'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Мои задания'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.getTopLeft(find.text('Твой день')).dy,
        lessThan(tester.getTopLeft(find.text('Мои задания')).dy),
      );
      expect(find.text('Твои семейные монеты'), findsNothing);
      await tester.tap(find.byType(FamilyCoinButton));
      await tester.pump();
      expect(find.text('Открыты монеты'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
