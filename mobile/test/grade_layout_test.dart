import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/school_screen.dart';

import 'field_layout_test.dart' show mountFields, revealField;
import 'support/calendar_results_fixture.dart';

void main() {
  for (final count in [3, 4, 8]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('one full-height results scroll: $count rows, scale $scale', (
        tester,
      ) async {
        final repo = ResultsFixture();
        addTearDown(() {
          repo.client.close();
          repo.dispose();
        });
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final school = repo.snapshot!['schedules'][0] as Map;
        school['weekdays'] = '[1,6]';
        school['activities'] = jsonEncode([
          for (var i = 0; i < count; i++)
            {
              'id': i.toRadixString(16).padLeft(32, '0'),
              'title': 'Предмет ${i + 1}',
              'start': '09:00',
              'end': '09:40',
            },
        ]);
        repo.snapshot!['tasks'] = [];
        await mountFields(
          tester,
          SchoolScreen(
            repository: repo,
            gradesOnly: true,
            initialDay: DateTime(2026, 10, 12),
            perform: (action) async {
              await action();
            },
          ),
          scale: scale,
        );
        for (final weekend in [false, true]) {
          expect(find.byType(Scrollable), findsOneWidget);
          final scroll = find.byType(Scrollable);
          expect(tester.getRect(scroll).bottom, greaterThan(780));
          await revealField(tester, find.text('Предмет $count'));
          expect(find.text('Предмет $count').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (!weekend) {
            for (var i = 0; i < 5; i++) {
              await tester.tap(find.byTooltip('Следующий день'));
              await tester.pumpAndSettle();
            }
          }
        }
      });
    }
  }

  testWidgets('grade actions stay reachable with a long saved history', (
    tester,
  ) async {
    final repo = ResultsFixture();
    addTearDown(() {
      repo.client.close();
      repo.dispose();
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repo.snapshot!['schedules'] = [];
    repo.snapshot!['tasks'] = [];
    repo.snapshot!['grades'] = [
      for (var i = 0; i < 100; i++)
        {
          'id': '$i',
          'subject_id': 'old-subject',
          'event_title': 'Предмет $i',
          'date': '2026-10-12',
          'grade': 5,
          'note': '',
          'revision': 'a' * 64,
          'posted_amount': 25,
        },
    ];
    await mountFields(
      tester,
      SchoolScreen(
        repository: repo,
        gradesOnly: true,
        initialDay: DateTime(2026, 10, 12),
        perform: (action) async {
          await action();
        },
      ),
      scale: 1.5,
    );
    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.text('Предмет 99 · 5'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('result-delete-grade-99')),
      500,
      maxScrolls: 120,
      scrollable: find.byType(Scrollable),
    );
    expect(
      find.byKey(const ValueKey('result-delete-grade-99')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
