import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/repository.dart';

import 'calendar_test.dart' as data;
import 'field_layout_test.dart' show revealField;
import 'event_editor_times_test.dart' show timingEvent;

class CalendarActionFixture extends FamilyRepository {
  final writes = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? response;

  CalendarActionFixture() {
    endpoint = 'https://calendar.invalid';
    token = 'synthetic-calendar-session';
    online = true;
    snapshot = data.snapshot([
      {
        ...data.event('Личное событие семьи', '12:00', '13:00', kind: 'other'),
        'revision': 'a' * 64,
        'note': 'Личное примечание семьи',
        'activities': '[]',
      },
    ])..['user'] = {'id': 'parent', 'role': 'parent'};
  }

  void change(String kind, {bool restore = false}) {
    final oldToken = token;
    final oldEndpoint = endpoint;
    final oldGeneration = generation;
    switch (kind) {
      case 'session':
        token = 'different-synthetic-session';
      case 'endpoint':
        endpoint = 'https://different.invalid';
      case 'generation':
        generation++;
      case 'role':
        snapshot!['user']['role'] = 'child';
    }
    notifyListeners();
    if (restore) {
      token = oldToken;
      endpoint = oldEndpoint;
      generation = oldGeneration;
      snapshot!['user']['role'] = 'parent';
      notifyListeners();
    }
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    writes.add({
      'path': path,
      'method': method,
      'body': Map<String, dynamic>.from(body),
      'offline': offlineSubmission,
    });
    return response == null ? {'ok': true} : response!.future;
  }
}

Future<GlobalKey<NavigatorState>> mountCalendar(
  WidgetTester tester,
  CalendarActionFixture owner, {
  ValueNotifier<CalendarActionFixture>? selection,
  Future<void> Function(Future<Map<String, dynamic>> Function())? perform,
  Size size = const Size(420, 900),
  double scale = 1.3,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    if (owner.response?.isCompleted == false) {
      owner.response!.complete({'ok': true});
    }
    await tester.pumpWidget(const SizedBox.shrink());
    owner.client.close();
    owner.dispose();
  });
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([owner, ?selection]),
          builder: (_, _) => CalendarScreen(
            repository: selection?.value ?? owner,
            initialDay: DateTime.utc(2026, 10, 12, 12),
            perform:
                perform ??
                (action) async {
                  await action();
                },
            openTasks: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigator;
}

Future<void> openEventActions(WidgetTester tester) async {
  await revealField(tester, find.text('Личное событие семьи'));
  await tester.tap(find.text('Личное событие семьи'));
  await tester.pumpAndSettle();
}

Future<void> openEditor(WidgetTester tester) async {
  await openEventActions(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Изменить событие'));
  await tester.pumpAndSettle();
  expect(find.byType(CalendarEditor), findsOneWidget);
}

Future<void> openDelete(WidgetTester tester) async {
  await openEventActions(tester);
  await tester.tap(find.widgetWithText(TextButton, 'Удалить событие'));
  await tester.pumpAndSettle();
  expect(find.text('Удалить событие?'), findsOneWidget);
}

void cover(GlobalKey<NavigatorState> navigator) {
  unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Другой важный экран')),
      ),
    ),
  );
}

void main() {
  for (final lessons in [false, true]) {
    testWidgets(
      'closed ${lessons ? 'lesson correction' : 'time picker'} ignores its old accept button',
      (tester) async {
        final repo = CalendarActionFixture();
        if (lessons) {
          repo.snapshot!['schedules'] = [
            {
              ...timingEvent(outside: true),
              'title': 'Личное событие семьи',
              'revision': 'a' * 64,
            },
          ];
        }
        await mountCalendar(tester, repo);
        await openEditor(tester);
        if (lessons) {
          await tester.tap(find.byKey(const ValueKey('event-save')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('event-fix-lesson-times')),
          );
        } else {
          await revealField(tester, find.byKey(const ValueKey('event-start')));
          await tester.tap(find.byKey(const ValueKey('event-start')));
        }
        await tester.pumpAndSettle();
        final button = lessons
            ? find.byKey(const ValueKey('apply-lesson-times'))
            : find.widgetWithText(TextButton, 'Готово');
        final old = tester.widget<TextButton>(button).onPressed!;
        await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
        await tester.pumpAndSettle();
        expect(find.byType(CalendarEditor), findsOneWidget);
        old();
        await tester.pumpAndSettle();
        expect(find.byType(CalendarEditor), findsOneWidget);
        expect(repo.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'calendar signout before first editor frame hides the captured form',
    (tester) async {
      final repo = CalendarActionFixture();
      await mountCalendar(tester, repo);
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Добавить событие'),
          )
          .onPressed!();
      repo.token = null;
      repo.snapshot = null;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Нужно открыть окно заново'), findsOneWidget);
      expect(repo.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('old calendar add cannot reopen after access was restored', (
    tester,
  ) async {
    final repo = CalendarActionFixture();
    await mountCalendar(tester, repo);
    final add = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Добавить событие'),
        )
        .onPressed!;
    repo.change('session', restore: true);
    add();
    await tester.pumpAndSettle();
    expect(find.byType(CalendarEditor), findsNothing);
    expect(repo.writes, isEmpty);
  });

  testWidgets('calendar opens a single sheet for repeated taps', (
    tester,
  ) async {
    final repo = CalendarActionFixture();
    await mountCalendar(tester, repo);
    await revealField(tester, find.text('Личное событие семьи'));
    final point = tester.getCenter(find.text('Личное событие семьи'));
    await tester.tapAt(point);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(repo.writes, isEmpty);
  });

  testWidgets('deferred calendar deletion rechecks its captured owner', (
    tester,
  ) async {
    final repo = CalendarActionFixture();
    final gate = Completer<void>();
    Object? rejected;
    await mountCalendar(
      tester,
      repo,
      perform: (action) async {
        await gate.future;
        try {
          await action();
        } catch (failure) {
          rejected = failure;
        }
      },
    );
    await openDelete(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить'));
    await tester.pump();
    repo.change('endpoint', restore: true);
    gate.complete();
    await tester.pumpAndSettle();
    expect(rejected, isA<ApiFailure>());
    expect(repo.writes, isEmpty);
  });

  testWidgets('offline deletion keeps the selected revision in its queue', (
    tester,
  ) async {
    final repo = CalendarActionFixture()..online = false;
    await mountCalendar(tester, repo);
    await openDelete(tester);
    final confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Подтвердить'))
        .onPressed!;
    confirm();
    confirm();
    await tester.pumpAndSettle();
    expect(repo.writes, hasLength(1));
    expect(repo.writes.single['offline'], isTrue);
    expect((repo.writes.single['body'] as Map)['expected_revision'], 'a' * 64);
  });

  testWidgets(
    'calendar time picker masks access loss and preserves a covering route',
    (tester) async {
      final repo = CalendarActionFixture();
      final navigator = await mountCalendar(tester, repo);
      await openEditor(tester);
      await revealField(tester, find.byKey(const ValueKey('event-start')));
      await tester.tap(find.byKey(const ValueKey('event-start')));
      await tester.pumpAndSettle();
      final ok = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Готово'))
          .onPressed!;
      final cancel = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Отмена'))
          .onPressed!;
      cover(navigator);
      await tester.pumpAndSettle();
      ok();
      cancel();
      await tester.pumpAndSettle();
      expect(find.text('Другой важный экран'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      repo.change('role', restore: true);
      await tester.pumpAndSettle();
      ok();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('time-hour')), findsNothing);
      expect(repo.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calendar date confirmation is local and preserves calendar selection',
    (tester) async {
      final repo = CalendarActionFixture();
      final navigator = await mountCalendar(tester, repo);
      await openEditor(tester);
      final date = find.widgetWithText(OutlinedButton, 'Дата: Пн, 12.10.2026');
      await revealField(tester, date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      final localization = MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)),
      );
      tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime(2026, 10, 15));
      await tester.pumpAndSettle();
      final ok = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, localization.okButtonLabel),
          )
          .onPressed!;
      cover(navigator);
      await tester.pumpAndSettle();
      ok();
      await tester.pumpAndSettle();
      expect(find.text('Другой важный экран'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      ok();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();
      expect((repo.writes.single['body'] as Map)['date'], '2026-10-15');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar date retains typed date entry', (tester) async {
    final repo = CalendarActionFixture();
    await mountCalendar(tester, repo);
    await openEditor(tester);
    final date = find.widgetWithText(OutlinedButton, 'Дата: Пн, 12.10.2026');
    await revealField(tester, date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    final localization = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    );
    await tester.tap(find.byTooltip(localization.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(InputDatePickerFormField),
        matching: find.byType(TextFormField),
      ),
      '10/20/2026',
    );
    await tester.tap(
      find.widgetWithText(TextButton, localization.okButtonLabel),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('event-save')));
    await tester.pumpAndSettle();
    expect((repo.writes.single['body'] as Map)['date'], '2026-10-20');
  });

  for (final correct in [false, true]) {
    testWidgets(
      'lesson ${correct ? 'correction' : 'conflict'} masks restored access',
      (tester) async {
        final repo = CalendarActionFixture();
        repo.snapshot!['schedules'] = [
          {
            ...timingEvent(outside: true),
            'title': 'Личное событие семьи',
            'revision': 'a' * 64,
          },
        ];
        final navigator = await mountCalendar(tester, repo);
        await openEditor(tester);
        await tester.tap(find.byKey(const ValueKey('event-save')));
        await tester.pumpAndSettle();
        if (correct) {
          await tester.tap(
            find.byKey(const ValueKey('event-fix-lesson-times')),
          );
          await tester.pumpAndSettle();
        }
        final key = ValueKey(
          correct ? 'apply-lesson-times' : 'event-use-lesson-times',
        );
        final old = tester
            .widget<ButtonStyleButton>(find.byKey(key))
            .onPressed!;
        cover(navigator);
        await tester.pumpAndSettle();
        old();
        await tester.pumpAndSettle();
        expect(find.text('Другой важный экран'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        repo.change('generation', restore: true);
        await tester.pumpAndSettle();
        old();
        await tester.pumpAndSettle();
        expect(find.text('Нужно открыть окно заново'), findsWidgets);
        expect(repo.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final kind in ['session', 'endpoint', 'generation', 'role']) {
    testWidgets('calendar sheet stays invalid after transient $kind loss', (
      tester,
    ) async {
      final repo = CalendarActionFixture();
      await mountCalendar(tester, repo);
      await openEventActions(tester);
      final oldEdit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Изменить событие'),
          )
          .onPressed!;
      repo.change(kind, restore: true);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Личное примечание семьи'),
        ),
        findsNothing,
      );
      expect(find.text('Нужно открыть окно заново'), findsOneWidget);
      oldEdit();
      await tester.pumpAndSettle();
      expect(find.byType(CalendarEditor), findsNothing);
      expect(repo.writes, isEmpty);
    });
    testWidgets(
      'calendar editor masks fields and blocks old save after $kind loss',
      (tester) async {
        final repo = CalendarActionFixture();
        await mountCalendar(tester, repo);
        await openEditor(tester);
        final save = tester
            .widget<FilledButton>(find.byKey(const ValueKey('event-save')))
            .onPressed!;
        repo.change(kind, restore: kind == 'role');
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('Нужно открыть окно заново'), findsOneWidget);
        save();
        await tester.pumpAndSettle();
        expect(repo.writes, isEmpty);
      },
    );
  }

  testWidgets('calendar sheet stale edit preserves covering route', (
    tester,
  ) async {
    final repo = CalendarActionFixture();
    final navigator = await mountCalendar(tester, repo);
    await openEventActions(tester);
    final edit = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Изменить событие'),
        )
        .onPressed!;
    cover(navigator);
    await tester.pumpAndSettle();
    edit();
    await tester.pumpAndSettle();
    expect(find.text('Другой важный экран'), findsOneWidget);
    expect(find.byType(CalendarEditor), findsNothing);
  });

  testWidgets('calendar delete old confirm and back preserve covering route', (
    tester,
  ) async {
    final repo = CalendarActionFixture();
    final navigator = await mountCalendar(tester, repo);
    await openDelete(tester);
    final confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Подтвердить'))
        .onPressed!;
    final back = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Назад'))
        .onPressed!;
    cover(navigator);
    await tester.pumpAndSettle();
    confirm();
    back();
    await tester.pumpAndSettle();
    expect(find.text('Другой важный экран'), findsOneWidget);
    expect(repo.writes, isEmpty);
  });

  testWidgets('calendar deletion cannot use a restored parent role', (
    tester,
  ) async {
    final repo = CalendarActionFixture();
    await mountCalendar(tester, repo);
    await openDelete(tester);
    final confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Подтвердить'))
        .onPressed!;
    repo.change('role', restore: true);
    await tester.pumpAndSettle();
    confirm();
    await tester.pumpAndSettle();
    expect(repo.writes, isEmpty);
  });

  testWidgets(
    'calendar actions cannot follow a replacement repository with the same user',
    (tester) async {
      final repo = CalendarActionFixture(), next = CalendarActionFixture();
      final selection = ValueNotifier(repo);
      addTearDown(() {
        selection.dispose();
        next.client.close();
        next.dispose();
      });
      await mountCalendar(tester, repo, selection: selection);
      await openDelete(tester);
      final confirm = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить'),
          )
          .onPressed!;
      selection.value = next;
      await tester.pumpAndSettle();
      confirm();
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      expect(next.writes, isEmpty);
    },
  );

  testWidgets(
    'late calendar save cannot close another route or be sent twice',
    (tester) async {
      final repo = CalendarActionFixture()..response = Completer();
      final navigator = await mountCalendar(tester, repo);
      await openEditor(tester);
      final save = tester
          .widget<FilledButton>(find.byKey(const ValueKey('event-save')))
          .onPressed!;
      save();
      await tester.pump();
      expect(repo.writes, hasLength(1));
      cover(navigator);
      await tester.pumpAndSettle();
      repo.response!.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(find.text('Другой важный экран'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      save();
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
    },
  );

  testWidgets(
    'offline calendar editor preserves date and queues one captured revision',
    (tester) async {
      final repo = CalendarActionFixture()..online = false;
      await mountCalendar(tester, repo);
      await openEditor(tester);
      final save = tester
          .widget<FilledButton>(find.byKey(const ValueKey('event-save')))
          .onPressed!;
      save();
      save();
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
      expect(repo.writes.single['offline'], isTrue);
      expect((repo.writes.single['body'] as Map)['date'], '2026-10-12');
      expect(
        (repo.writes.single['body'] as Map)['expected_revision'],
        'a' * 64,
      );
    },
  );
}
