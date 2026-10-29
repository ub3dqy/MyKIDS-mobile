import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/calendar_grid.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/event_style.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';

import 'calendar_test.dart' as fixture;
import 'field_layout_test.dart' show mountFields, revealField;

Map<String, dynamic> schoolBlock() => {
  ...fixture.event('Школа', '09:00', '14:00'),
  'note': 'Учебный день',
  'color': 'blue',
  'activities': jsonEncode([
    {'title': 'Математика', 'start': '09:00', 'end': '10:00'},
    {'title': 'Русский язык', 'start': '10:20', 'end': '11:00'},
  ]),
};

Future<void> revealEvent(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await revealField(tester, finder);
  await tester.pumpAndSettle();
}

void main() {
  test('block activities survive one day changes and morning overview', () {
    final data = fixture.snapshot([schoolBlock()]);
    final day = DateTime.utc(2026, 10, 12, 12);
    final block = calendarDay(data, day).single;
    expect(block.color, 'blue');
    expect(block.activities.map((item) => item.title), [
      'Математика',
      'Русский язык',
    ]);
    expect(morningEntries([block]).single.activities.length, 2);
    expect(calendarConflicts([block]), isEmpty);
    data['schedule_exceptions'] = [
      {
        'schedule_id': 'Школа',
        'date': '2026-10-12',
        'replacement': jsonEncode({
          'color': 'green',
          'activities': [
            {'title': 'Физика', 'start': '11:00', 'end': '12:00'},
          ],
        }),
      },
    ];
    final changed = calendarDay(data, day).single;
    expect(changed.color, 'green');
    expect(changed.activities.single.title, 'Физика');
    expect(calendarDay(data, DateTime.utc(2026, 10, 13)), isEmpty);
  });

  Future<void> editor(
    WidgetTester tester,
    Map<String, dynamic> initial,
    void Function(Map<String, dynamic>) saved,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = fixture.snapshot([]);
    await mountFields(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            child: const Text('Открыть'),
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<Map<String, dynamic>>(
                    MaterialPageRoute(
                      builder: (_) => CalendarEditor(
                        snapshot: data,
                        initial: initial,
                        day: familyClock(data, DateTime.utc(2026, 10, 12, 12)),
                      ),
                    ),
                  );
              if (result != null) saved(result);
            },
          ),
        ),
      ),
      scale: 1.4,
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'simple editor saves block, note and manual color without extra fields',
    (tester) async {
      Map<String, dynamic>? saved;
      await editor(tester, schoolBlock(), (value) => saved = value);
      expect(find.byKey(const ValueKey('event-kind')), findsNothing);
      expect(find.byKey(const ValueKey('event-subject')), findsNothing);
      expect(find.byKey(const ValueKey('event-place')), findsNothing);
      expect(find.byKey(const ValueKey('event-reminder')), findsNothing);
      await revealEvent(tester, find.byKey(const ValueKey('event-note')));
      await tester.enterText(
        find.byKey(const ValueKey('event-note')),
        'Взять тетради',
      );
      final color = find.byKey(const ValueKey('event-color-green'));
      await revealEvent(tester, color);
      await tester.tap(color);
      await revealEvent(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(saved!['color'], 'green');
      expect(saved!['note'], 'Взять тетради');
      expect(saved!['start'], '09:00');
      expect(saved!['end'], '14:00');
      expect((saved!['activities'] as List).map((item) => item['title']), [
        'Математика',
        'Русский язык',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('activity can be removed while another keeps its entered title', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await editor(tester, schoolBlock(), (value) => saved = value);
    final second = find.byKey(const ValueKey('activity-title-1'));
    await revealEvent(tester, second);
    await tester.enterText(second, 'Литература');
    await revealEvent(tester, find.byTooltip('Удалить занятие 1'));
    await tester.tap(find.byTooltip('Удалить занятие 1'));
    await tester.pump();
    await revealEvent(tester, find.byKey(const ValueKey('activity-title-0')));
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('activity-title-0')))
          .controller!
          .text,
      'Литература',
    );
    await revealEvent(tester, find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect((saved!['activities'] as List).single['title'], 'Литература');
    expect(tester.takeException(), isNull);
  });

  testWidgets('new activity gets both required times through the picker', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await editor(tester, {
      ...schoolBlock(),
      'activities': [],
    }, (value) => saved = value);
    await revealEvent(tester, find.text('Добавить занятие'));
    await tester.tap(find.text('Добавить занятие'));
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('activity-title-0'));
    await revealEvent(tester, name);
    await tester.enterText(name, 'Математика');
    Future<void> pick(String key, String hour, String minute) async {
      await revealEvent(tester, find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('time-hour')), hour);
      await tester.enterText(find.byKey(const ValueKey('time-minute')), minute);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Готово'));
      await tester.pumpAndSettle();
    }

    await pick('activity-start-0', '9', '0');
    await pick('activity-end-0', '10', '0');
    await revealEvent(tester, find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect((saved!['activities'] as List).single, {
      'title': 'Математика',
      'start': '09:00',
      'end': '10:00',
    });
    expect(tester.takeException(), isNull);
  });

  for (final sample in [
    (
      'outside',
      [
        {'title': 'Урок', 'start': '08:00', 'end': '10:00'},
      ],
      'Время не совпадает',
    ),
    (
      'overlap',
      [
        {'title': 'Первый', 'start': '09:00', 'end': '10:30'},
        {'title': 'Второй', 'start': '10:20', 'end': '11:00'},
      ],
      'Занятия пересекаются',
    ),
    (
      'reversed',
      [
        {'title': 'Урок', 'start': '10:00', 'end': '09:00'},
      ],
      'Проверьте время занятия',
    ),
  ]) {
    testWidgets('editor rejects ${sample.$1} activities', (tester) async {
      Map<String, dynamic>? saved;
      await editor(tester, {
        ...schoolBlock(),
        'activities': sample.$2,
      }, (value) => saved = value);
      await revealEvent(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      expect(find.text(sample.$3), findsOneWidget);
      expect(saved, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final role in ['parent', 'child', 'relative']) {
    testWidgets('all roles open full block; only parent gets editing: $role', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FamilyRepository()
        ..endpoint = 'https://event-blocks.invalid'
        ..token = 'synthetic-event-block-session'
        ..online = true;
      repo.snapshot = fixture.snapshot([schoolBlock()])
        ..['user'] = {'id': role, 'role': role};
      await mountFields(
        tester,
        Scaffold(
          body: CalendarScreen(
            repository: repo,
            initialDay: DateTime.utc(2026, 10, 12, 12),
            perform: (action) async {
              await action();
            },
            openTasks: (_) {},
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Школа'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await revealEvent(tester, find.text('Школа'));
      await tester.tap(find.text('Школа'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(EventActivities), findsWidgets);
      expect(find.text('Русский язык'), findsWidgets);
      expect(
        find.text('Изменить событие'),
        role == 'parent' ? findsOneWidget : findsNothing,
      );
      expect(find.text('Свободное время'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    });
  }

  testWidgets('timeline handles many simultaneous events at large font', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = fixture.snapshot([
      for (var i = 0; i < 12; i++) fixture.event('Дело $i', '09:00', '10:00'),
    ]);
    final day = familyClock(data, DateTime.utc(2026, 10, 12, 12));
    await mountFields(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CalendarTimeline(
            days: [day],
            entries: (_) => calendarDay(data, day),
            open: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Дело 11'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('task ending at midnight keeps its full hour on the timeline', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = fixture.snapshot([])
      ..['tasks'] = [
        {
          'id': 'night',
          'title': 'Ночное дело',
          'status': 'assigned',
          'planned_start': '2026-10-12T20:00:00Z',
          'planned_end': '2026-10-12T21:00:00Z',
          'due_at': '2026-10-12T21:00:00Z',
        },
      ];
    final day = familyClock(data, DateTime.utc(2026, 10, 12, 12));
    await mountFields(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CalendarTimeline(
            days: [day],
            entries: (_) => calendarDay(data, day),
            open: (_) {},
          ),
        ),
      ),
    );
    final block = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.label ?? '').startsWith('Ночное дело,'),
    );
    expect(tester.getSize(block).height, greaterThanOrEqualTo(48));
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('24:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty time cell opens creation with its date and hour', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FamilyRepository()
      ..endpoint = 'https://event-blocks.invalid'
      ..token = 'synthetic-event-block-session'
      ..online = true;
    repo.snapshot = fixture.snapshot([])
      ..['user'] = {'id': 'papa', 'role': 'parent'};
    await mountFields(
      tester,
      Scaffold(
        body: CalendarScreen(
          repository: repo,
          initialDay: DateTime.utc(2026, 10, 12, 12),
          perform: (action) async {
            await action();
          },
          openTasks: (_) {},
        ),
      ),
    );
    final cell = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Добавить событие: Пн, 12.10.2026, 7:00',
    );
    await revealEvent(tester, cell);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarEditor), findsOneWidget);
    expect(find.text('Начало: 07:00'), findsOneWidget);
    expect(find.text('Окончание: 08:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });
}
