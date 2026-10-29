import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/money_screen.dart';

import 'activity_lists_test.dart' show ActivityFixture;
import 'field_layout_test.dart' show mountFields, revealField;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/local_auth');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ActivityFixture repo;
  late int authentications;
  setUp(() {
    repo = ActivityFixture()..token = 'synthetic-penalty-owner';
    repo.snapshot!['tasks'] = [
      {
        'id': 'morning',
        'title': 'Умывание с чисткой зубов',
        'version': 1,
        'planned_start': '2026-10-29T04:30:00Z',
        'planned_end': '2026-10-29T05:00:00Z',
        'due_at': '2026-10-29T20:00:00Z',
      },
      {
        'id': 'evening',
        'title': 'Умывание с чисткой зубов',
        'version': 1,
        'planned_start': '2026-10-28T18:30:00Z',
        'planned_end': '2026-10-28T19:00:00Z',
        'due_at': '2026-10-28T20:00:00Z',
      },
    ];
    repo.snapshot!['penalties'] = [
      for (final id in ['morning', 'evening'])
        {
          'id': 'fine-$id',
          'source_type': 'task',
          'source_id': id,
          'source_version': 1,
          'status': 'pending',
          'reason': 'Не выполнено: Умывание с чисткой зубов',
          'amount': 500,
        },
    ];
    authentications = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'stopAuthentication') return true;
      expect(call.method, 'authenticate');
      authentications++;
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    repo.client.close();
    repo.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    await mountFields(
      tester,
      Scaffold(
        body: MoneyScreen(
          repository: repo,
          perform: (operation) async {
            await operation();
          },
        ),
      ),
      scale: 1.6,
    );
  }

  Finder applyEvening() => find.descendant(
    of: find.byKey(const ValueKey('penalty-fine-evening')),
    matching: find.widgetWithText(FilledButton, 'Применить'),
  );

  Future<void> consent(WidgetTester tester) async {
    await open(tester);
    final button = applyEvening();
    await revealField(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'same-title penalties show exact family dates and windows; consent binds the selected occurrence',
    (tester) async {
      await consent(tester);
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('28.10.2026 21:30 – 22:00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('29.10.2026'),
        ),
        findsNothing,
      );
      expect(authentications, 0);
      expect(repo.changes, isEmpty);
      final button = find.widgetWithText(FilledButton, 'Подтвердить');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(authentications, 1);
      expect(repo.changes, ['/v1/penalties/fine-evening/approve']);
      expect(tester.takeException(), isNull);
    },
  );

  for (final retarget in [false, true]) {
    testWidgets(
      'changed ${retarget ? 'source' : 'window'} invalidates old penalty consent',
      (tester) async {
        await consent(tester);
        final callback = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Подтвердить'),
            )
            .onPressed!;
        if (retarget) {
          repo.snapshot!['penalties'][1]['source_id'] = 'morning';
        } else {
          repo.snapshot!['tasks'][1]['planned_end'] = '2026-10-28T19:30:00Z';
        }
        repo.notifyListeners();
        await tester.pumpAndSettle();
        callback();
        await tester.pumpAndSettle();
        expect(find.text('Подтверждение недоступно'), findsOneWidget);
        expect(authentications, 0);
        expect(repo.changes, isEmpty);
        await tester.tap(find.widgetWithText(TextButton, 'Закрыть'));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('a missing task disables ambiguous financial confirmation', (
    tester,
  ) async {
    repo.snapshot!['tasks'] = [];
    await open(tester);
    final button = applyEvening();
    await revealField(tester, button);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(
      find.textContaining('Дата и время задания недоступны.'),
      findsNWidgets(2),
    );
    expect(authentications, 0);
    expect(repo.changes, isEmpty);
  });
}
