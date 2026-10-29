import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/event_editor.dart';
import 'package:mykids_family/event_time_rules.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/visuals.dart';

import 'calendar_test.dart' as fixture;

const firstLessonId = '11111111111111111111111111111111';
const lastLessonId = '22222222222222222222222222222222';
Map<String, dynamic> timingEvent({
  bool outside = false,
  bool overlap = false,
}) => {
  ...fixture.event('Школа', '09:00', '13:00'),
  'note': 'Учебный день',
  'color': 'blue',
  'activities': jsonEncode([
    {
      'id': firstLessonId,
      'title': 'Математика',
      'start': outside ? '08:00' : '09:00',
      'end': overlap ? '10:30' : '10:00',
    },
    {
      'id': lastLessonId,
      'title': 'Русский язык',
      'start': overlap ? '10:20' : '12:00',
      'end': outside ? '14:00' : '13:00',
    },
  ]),
};

Future<void> mountTimingEditor(
  WidgetTester tester,
  Map<String, dynamic> initial,
  void Function(Map<String, dynamic>) saved, {
  double keyboard = 0,
  double scale = 1.4,
  bool native = false,
}) async {
  final data = fixture.snapshot([]);
  if (!native) {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: familyTheme(false),
      locale: const Locale('ru'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ru')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: native
              ? null
              : EdgeInsets.only(bottom: keyboard == 0 ? 48 : 0),
          viewPadding: native ? null : const EdgeInsets.only(bottom: 48),
          viewInsets: native ? null : EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
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
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

Future<void> tapTiming(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> pickTiming(
  WidgetTester tester,
  String key,
  int hour,
  int minute,
) async {
  await tapTiming(tester, find.byKey(ValueKey(key)));
  await tester.enterText(find.byKey(const ValueKey('time-hour')), '$hour');
  await tester.enterText(find.byKey(const ValueKey('time-minute')), '$minute');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Готово'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'late day addition is rejected without wrapping or hiding save under keyboard',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountTimingEditor(
        tester,
        {
          ...timingEvent(),
          'start': '23:00',
          'end': '23:59',
          'activities': jsonEncode([
            {
              'id': firstLessonId,
              'title': 'Позднее занятие',
              'start': '23:00',
              'end': '23:55',
            },
          ]),
        },
        (_) => fail('Must not save'),
        keyboard: 300,
        scale: 2,
      );
      await tapTiming(tester, find.text('Добавить занятие'));
      expect(find.byKey(const ValueKey('activity-title-1')), findsNothing);
      expect(find.textContaining('с перерывом 10 минут'), findsOneWidget);
      final save = find.byKey(const ValueKey('event-save'));
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(500));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('next lesson waits for a valid previous end', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountTimingEditor(tester, {
      ...timingEvent(),
      'activities': '[]',
    }, (_) => fail('Must not save'));
    await tapTiming(tester, find.text('Добавить занятие'));
    await tapTiming(tester, find.text('Добавить занятие'));
    expect(find.byKey(const ValueKey('activity-title-1')), findsNothing);
    expect(find.textContaining('предыдущего занятия'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'ten minute breaks cross hour boundaries but never wrap into another day',
    () {
      expect(
        nextLessonStart(const TimeOfDay(hour: 9, minute: 0)),
        const TimeOfDay(hour: 9, minute: 10),
      );
      expect(
        nextLessonStart(const TimeOfDay(hour: 9, minute: 55)),
        const TimeOfDay(hour: 10, minute: 5),
      );
      expect(
        nextLessonStart(const TimeOfDay(hour: 23, minute: 48)),
        const TimeOfDay(hour: 23, minute: 58),
      );
      expect(nextLessonStart(const TimeOfDay(hour: 23, minute: 49)), isNull);
      expect(nextLessonStart(const TimeOfDay(hour: 23, minute: 55)), isNull);
    },
  );
  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> initial,
    void Function(Map<String, dynamic>) saved, {
    double keyboard = 0,
    double scale = 1.4,
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountTimingEditor(
      tester,
      initial,
      saved,
      keyboard: keyboard,
      scale: scale,
    );
  }

  test('nested overlap warning names the lesson that actually overlaps', () {
    final problem = lessonTimeProblem(
      const [
        EventLessonTime(
          'Длинное занятие',
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 12, minute: 0),
        ),
        EventLessonTime(
          'Короткое занятие',
          TimeOfDay(hour: 10, minute: 0),
          TimeOfDay(hour: 10, minute: 30),
        ),
        EventLessonTime(
          'Третье занятие',
          TimeOfDay(hour: 11, minute: 0),
          TimeOfDay(hour: 11, minute: 30),
        ),
      ],
      const TimeOfDay(hour: 8, minute: 0),
      const TimeOfDay(hour: 13, minute: 0),
    );
    expect(problem?.kind, LessonProblemKind.overlap);
    expect(problem?.message, contains('Длинное занятие'));
    expect(
      lessonTimeProblem(
        const [
          EventLessonTime(
            'Урок',
            TimeOfDay(hour: 9, minute: 0),
            TimeOfDay(hour: 10, minute: 0),
          ),
        ],
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 13, minute: 0),
        allowOverlap: true,
      ),
      isNull,
    );
  });

  testWidgets('choosing lesson times expands event and keeps identities', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await mount(tester, timingEvent(outside: true), (value) => saved = value);
    await tapTiming(tester, find.byKey(const ValueKey('event-save')));
    expect(find.text('Время не совпадает'), findsOneWidget);
    expect(saved, isNull);
    await tapTiming(
      tester,
      find.byKey(const ValueKey('event-use-lesson-times')),
    );
    expect(saved, isNull);
    await tapTiming(tester, find.byKey(const ValueKey('event-save')));
    expect(saved!['start'], '08:00');
    expect(saved!['end'], '14:00');
    expect((saved!['activities'] as List).map((row) => row['id']), [
      firstLessonId,
      lastLessonId,
    ]);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'keeping event time lets the user correct both outside endpoints',
    (tester) async {
      Map<String, dynamic>? saved;
      await mount(tester, timingEvent(outside: true), (value) => saved = value);
      await tapTiming(tester, find.byKey(const ValueKey('event-save')));
      await tapTiming(
        tester,
        find.byKey(const ValueKey('event-fix-lesson-times')),
      );
      await pickTiming(tester, 'correct-activity-start-0', 9, 0);
      await pickTiming(tester, 'correct-activity-end-1', 13, 0);
      await tapTiming(tester, find.byKey(const ValueKey('apply-lesson-times')));
      await tapTiming(tester, find.byKey(const ValueKey('event-save')));
      expect(saved!['start'], '09:00');
      expect(saved!['end'], '13:00');
      expect(saved!['activities'][0]['start'], '09:00');
      expect(saved!['activities'][1]['end'], '13:00');
      expect(saved!['activities'][0]['id'], firstLessonId);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'overlapping lessons need correction; touching endpoints are allowed',
    (tester) async {
      Map<String, dynamic>? saved;
      await mount(tester, timingEvent(overlap: true), (value) => saved = value);
      await tapTiming(tester, find.byKey(const ValueKey('event-save')));
      expect(find.text('Занятия пересекаются'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('event-use-lesson-times')),
        findsNothing,
      );
      await tapTiming(
        tester,
        find.byKey(const ValueKey('event-fix-lesson-times')),
      );
      await tapTiming(tester, find.byKey(const ValueKey('apply-lesson-times')));
      expect(
        find.byKey(const ValueKey('lesson-time-correction')),
        findsOneWidget,
      );
      await pickTiming(tester, 'correct-activity-start-1', 10, 30);
      await tapTiming(tester, find.byKey(const ValueKey('apply-lesson-times')));
      await tapTiming(tester, find.byKey(const ValueKey('event-save')));
      expect(saved!['activities'][1]['start'], '10:30');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cancelling time corrections keeps the original draft', (
    tester,
  ) async {
    await mount(
      tester,
      timingEvent(outside: true),
      (_) => fail('Must not save'),
    );
    await tapTiming(tester, find.byKey(const ValueKey('event-save')));
    await tapTiming(
      tester,
      find.byKey(const ValueKey('event-fix-lesson-times')),
    );
    await pickTiming(tester, 'correct-activity-start-0', 9, 0);
    await tapTiming(tester, find.widgetWithText(TextButton, 'Отмена').last);
    final original = find.byKey(const ValueKey('activity-start-0'));
    await tester.ensureVisible(original);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: original, matching: find.text('Начало: 08:00')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'adding the second and third lesson fills previous end plus ten minutes',
    (tester) async {
      final initial = {
        ...timingEvent(),
        'start': '08:00',
        'activities': jsonEncode([
          {
            'id': firstLessonId,
            'title': 'Урок 1',
            'start': '08:00',
            'end': '09:00',
          },
        ]),
      };
      await mount(tester, initial, (_) => fail('Must not save'));
      await tapTiming(tester, find.text('Добавить занятие'));
      final second = find.byKey(const ValueKey('activity-start-1'));
      expect(
        find.descendant(of: second, matching: find.text('Начало: 09:10')),
        findsOneWidget,
      );
      await pickTiming(tester, 'activity-end-1', 10, 0);
      await tapTiming(tester, find.text('Добавить занятие'));
      final third = find.byKey(const ValueKey('activity-start-2'));
      expect(
        find.descendant(of: third, matching: find.text('Начало: 10:10')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'overlap can be confirmed and saved without changing lesson times',
    (tester) async {
      Map<String, dynamic>? saved;
      await mount(tester, timingEvent(overlap: true), (value) => saved = value);
      await tapTiming(tester, find.byKey(const ValueKey('event-save')));
      expect(find.text('Занятия пересекаются'), findsOneWidget);
      await tapTiming(tester, find.byKey(const ValueKey('event-keep-overlap')));
      expect(saved!['allow_overlaps'], true);
      expect(saved!['activities'][0]['end'], '10:30');
      expect(saved!['activities'][1]['start'], '10:20');
      expect(tester.takeException(), isNull);
    },
  );
  for (final keyboard in [0.0, 300.0]) {
    testWidgets(
      'save stays above system navigation and keyboard $keyboard with large text',
      (tester) async {
        Map<String, dynamic>? saved;
        await mount(
          tester,
          {...timingEvent(), 'date': null, 'weekdays': '[1]'},
          (value) => saved = value,
          keyboard: keyboard,
          scale: 2,
        );
        final save = find.byKey(const ValueKey('event-save'));
        expect(save.hitTestable(), findsOneWidget);
        final rect = tester.getRect(save);
        expect(
          rect.bottom,
          lessThanOrEqualTo(800 - (keyboard == 0 ? 48 : keyboard)),
        );
        expect(rect.top, greaterThanOrEqualTo(0));
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
