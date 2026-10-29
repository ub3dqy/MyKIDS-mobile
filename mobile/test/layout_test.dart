import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/visuals.dart';

class ViewRepository extends FamilyRepository {
  ViewRepository(String role) {
    variant = role;
    snapshot = {
      'user': {'name': 'Проверочное длинное имя', 'role': role},
      'family': {'timezone': 'Europe/Moscow'},
      'balance': {'available': 1000000},
      'tasks': <Map<String, dynamic>>[],
    };
  }
  @override
  Future<List<Map<String, dynamic>>> pending() async => [];
}

void main() {
  for (final role in ['child', 'parent', 'relative']) {
    testWidgets('today remains readable at 320px and double text size: $role', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = ViewRepository(role);
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(role == 'child'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: TodayScreen(repository: repo, openPage: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Чаты и звонки'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Чаты и звонки'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    });
  }
}
