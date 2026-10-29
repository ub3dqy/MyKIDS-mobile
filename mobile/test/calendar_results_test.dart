import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_results.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/school_screen.dart';

import 'field_layout_test.dart' show mountFields, revealField;
import 'support/calendar_results_fixture.dart';

void main() {
  final day = DateTime(2026, 10, 12);
  test('family timezone preserves selected civil date', () {
    final repo = ResultsFixture();
    repo.snapshot!['family']['timezone'] = 'America/Los_Angeles';
    expect(
      calendarResultItems(
        repo.snapshot!,
        day,
      ).where((item) => item.title == 'Математика').length,
      1,
    );
  });
  test(
    'calendar lessons, recurrence and exceptions supply dated result choices',
    () {
      final repo = ResultsFixture();
      final data = repo.snapshot!;
      expect(
        calendarResultItems(data, day).any((item) => item.title == 'Школа'),
        isFalse,
      );
      expect(calendarResultItems(data, day).map((item) => item.title), [
        'Математика',
        'Русский язык',
        'Помочь бабушке',
      ]);
      expect(
        calendarResultItems(
          data,
          DateTime(2026, 10, 13),
        ).map((item) => item.title),
        ['Математика', 'Русский язык'],
      );
      data['schedule_exceptions'] = [
        <String, dynamic>{
          'schedule_id': 'school',
          'date': '2026-10-13',
          'replacement': jsonEncode({
            'activities': [
              {
                'id': russianIdentity,
                'title': 'Физика',
                'start': '11:00',
                'end': '12:00',
              },
            ],
          }),
        },
      ];
      expect(
        calendarResultItems(
          data,
          DateTime(2026, 10, 13),
        ).map((item) => item.title),
        ['Физика'],
      );
      data['schedule_exceptions'][0]['replacement'] = null;
      expect(calendarResultItems(data, DateTime(2026, 10, 13)), isEmpty);
    },
  );

  test(
    'only school subjects and explicit standalone subjects accept grades',
    () {
      final repo = ResultsFixture();
      final school = repo.snapshot!['schedules'][0] as Map<String, dynamic>;
      school['kind'] =
          'other'; // Real events made by the former minimal editor.
      expect(
        calendarResultItems(
          repo.snapshot!,
          day,
        ).where((item) => item.canGrade).length,
        2,
      );
      school['title'] = 'Музыкальная школа';
      expect(
        calendarResultItems(repo.snapshot!, day).where((item) => item.canGrade),
        isEmpty,
      );
      school['grade_subjects'] = true;
      expect(
        calendarResultItems(
          repo.snapshot!,
          day,
        ).where((item) => item.canGrade).length,
        2,
      );
      school['grade_subjects'] = false;
      school['kind'] = 'school';
      expect(
        calendarResultItems(repo.snapshot!, day).where((item) => item.canGrade),
        isEmpty,
      );
      repo.client.close();
      repo.dispose();
    },
  );

  test(
    'a multi-day task supplies one choice per date including its deadline',
    () {
      final repo = ResultsFixture();
      repo.snapshot!['schedules'] = [];
      final task = repo.snapshot!['tasks'][0] as Map<String, dynamic>;
      task['planned_start'] = '2026-10-11T20:00:00Z';
      task['planned_end'] = '2026-10-12T21:00:00Z';
      task['due_at'] = '2026-10-13T17:00:00Z';
      expect(calendarResultItems(repo.snapshot!, day).length, 1);
      expect(
        calendarResultItems(repo.snapshot!, DateTime(2026, 10, 13)).length,
        1,
      );
      task['status'] = 'cancelled';
      expect(calendarResultItems(repo.snapshot!, day), isEmpty);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    ResultsFixture repo, {
    double scale = 2,
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountFields(
      tester,
      SchoolScreen(
        repository: repo,
        gradesOnly: true,
        initialDay: day,
        perform: (action) async {
          await action();
        },
      ),
      scale: scale,
    );
  }

  testWidgets(
    'parent selects a dated lesson and saves its grade without manual subject creation',
    (tester) async {
      final repo = ResultsFixture();
      await mount(tester, repo);
      expect(find.text('Добавить предмет'), findsNothing);
      final math = find.byKey(
        const ValueKey('result-grade-schedule:school:2026-10-12:$mathIdentity'),
      );
      await revealField(tester, math);
      await tester.tap(math);
      await tester.pumpAndSettle();
      expect(find.text('Оценка: Математика'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.changes.single['body'], {
        'schedule_id': 'school',
        'activity_id': mathIdentity,
        'date': '2026-10-12',
        'grade': 5,
      });
      expect(tester.takeException(), isNull);
      expect(find.byType(FamilyForm), findsNothing);
      await tester.tap(find.byTooltip('Следующий день'));
      await tester.pumpAndSettle();
      expect(find.text('Вт, 13.10.2026'), findsOneWidget);
      final nextMath = find.byKey(
        const ValueKey('result-grade-schedule:school:2026-10-13:$mathIdentity'),
      );
      await revealField(tester, nextMath);
      expect(find.text('Изменить оценку'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new calendar event appears in an already open section and old grades remain',
    (tester) async {
      final repo = ResultsFixture();
      repo.snapshot!['schedules'] = [];
      repo.snapshot!['tasks'] = [];
      await mount(tester, repo);
      expect(
        find.textContaining('На эту дату школьных предметов и заданий нет'),
        findsOneWidget,
      );
      repo.snapshot!['schedules'] = [ResultsFixture.schoolEvent()];
      repo.snapshot!['grades'] = [
        {
          'id': 'old',
          'subject_id': 'old-subject',
          'date': '2026-10-12',
          'grade': 4,
          'note': 'Запись',
        },
      ];
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Школа'), findsNothing);
      expect(find.text('Математика'), findsOneWidget);
      await revealField(
        tester,
        find.byKey(const ValueKey('result-history-old')),
      );
      expect(find.text('Прежний предмет · 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in ['parent', 'relative', 'child']) {
    testWidgets(
      '$role receives only its permitted task action; rewards are fixed by author',
      (tester) async {
        final repo = ResultsFixture(role: role);
        repo.snapshot!['schedules'] = [];
        await mount(tester, repo);
        final action = find.byKey(
          ValueKey(
            role == 'child' ? 'result-submit-help' : 'result-complete-help',
          ),
        );
        await revealField(tester, action);
        expect(
          find.textContaining('Награда после проверки: 70 монет'),
          findsOneWidget,
        );
        expect(find.text('Необязательное задание'), findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        if (role != 'child') {
          await tester.tap(find.widgetWithText(TextButton, 'Выполнено'));
          await tester.pumpAndSettle();
          expect(repo.changes.single['body'], {
            'action': 'complete',
            'date': '2026-10-12',
            'task_version': 3,
          });
          expect(find.text('Начислено: 70 монет.'), findsOneWidget);
        } else {
          expect(repo.changes.single['path'], '/v1/tasks/help/submissions');
          expect(repo.changes.single['offline'], isTrue);
          expect(repo.changes.single['body']['task_version'], 3);
          expect(
            find.byKey(const ValueKey('result-complete-help')),
            findsNothing,
          );
          expect(find.text('Начислено: 70 монет.'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('parent cannot skip mandatory photo or unapproved reward', (
    tester,
  ) async {
    final repo = ResultsFixture();
    repo.snapshot!['schedules'] = [];
    repo.snapshot!['tasks'][0]['require_photo'] = 1;
    repo.snapshot!['tasks'][0]['financial_approved'] = 0;
    await mount(tester, repo);
    final finder = find.byKey(const ValueKey('result-complete-help'));
    await revealField(tester, finder);
    expect(tester.widget<FilledButton>(finder).onPressed, isNull);
    expect(repo.changes, isEmpty);
  });
}
