import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/settings_screen.dart';
import 'package:mykids_family/task_screen.dart';

import 'calendar_creation_date_test.dart' show pickDate;
import 'calendar_keep_date_test.dart'
    show KeepDateFixture, openCalendarApp, expectSelected;
import 'calendar_removal_date_test.dart' show chosenDay;
import 'resume_refresh_test.dart' show pauseResumeApp;

class SectionFixture extends KeepDateFixture {
  int reconnects = 0;

  SectionFixture(super.selected, String role) : super(userRole: role) {
    snapshot!['balance'] = {'total': 20, 'reserved': 0, 'available': 20};
    snapshot!['user']['id'] = role;
    snapshot!['members'] = [
      {'id': role, 'name': 'Проверка', 'role': role, 'active': 1},
    ];
  }

  void replaceSnapshot({required bool connected}) {
    snapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(snapshot)) as Map,
    );
    online = connected;
    notifyListeners();
  }

  @override
  Future<void> reconnect() async {
    reconnects++;
    replaceSnapshot(connected: online);
  }
}

List<String> sectionsFor(String role) => [
  'Сегодня',
  'Задания',
  if (role != 'relative') 'Монеты',
  'Семья',
  'Настройки',
  if (role == 'child') 'Монеты вверху',
];

Future<void> openSection(WidgetTester tester, String section) async {
  if (section == 'Настройки') {
    await tester.tap(find.byTooltip('Настройки'));
  } else if (section == 'Монеты вверху') {
    await tester.tap(find.byType(FamilyCoinButton));
  } else {
    await tester.tap(find.text(section).last);
  }
  await tester.pumpAndSettle();
  expect(find.byType(CalendarScreen), findsNothing);
  expect(
    find.byType(switch (section) {
      'Сегодня' => TodayScreen,
      'Задания' => TaskScreen,
      'Монеты' || 'Монеты вверху' => MoneyScreen,
      'Семья' => FamilyScreen,
      _ => SettingsScreen,
    }),
    findsOneWidget,
  );
  if (section == 'Семья') {
    for (final tab in ['Контакты', 'Звонки', 'Чаты']) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pumpAndSettle();
    }
  }
}

Future<void> returnToSelection(
  WidgetTester tester,
  DateTime selected,
  String view,
) async {
  await tester.tap(find.text('Календарь').last);
  await tester.pumpAndSettle();
  await expectSelected(tester, selected, view);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'morning:child': dateOnly(familyClock(null)),
    });
  });

  for (final role in ['parent', 'child', 'relative']) {
    for (final view in ['День', 'Неделя', 'Месяц']) {
      for (final section in sectionsFor(role)) {
        for (final offset in [-8, 8]) {
          testWidgets('$role $view returns from $section to date $offset', (
            tester,
          ) async {
            final repo = SectionFixture(chosenDay(offset), role);
            await openCalendarApp(tester, repo);
            await tester.tap(find.widgetWithText(ChoiceChip, view));
            await tester.pumpAndSettle();
            final previousCalendar = tester.state(find.byType(CalendarScreen));
            await openSection(tester, section);
            expect(previousCalendar.mounted, isFalse);
            repo.replaceSnapshot(connected: offset > 0);
            await tester.pumpAndSettle();
            await returnToSelection(tester, repo.selected, view);
            expect(repo.mutations, isEmpty);
          });
        }
      }

      testWidgets('$role $view repeated section round trips keep latest date', (
        tester,
      ) async {
        final repo = SectionFixture(chosenDay(-8), role);
        await openCalendarApp(tester, repo);
        await tester.tap(find.widgetWithText(ChoiceChip, view));
        await tester.pumpAndSettle();
        var selected = repo.selected;
        for (final section in sectionsFor(role)) {
          await openSection(tester, section);
          final reconnects = repo.reconnects;
          pauseResumeApp(tester);
          repo.replaceSnapshot(connected: false);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(repo.reconnects, reconnects + 1);
          await returnToSelection(tester, selected, view);
          // A later choice must replace the remembered date on every round trip.
          final next = chosenDay(selected.day == repo.selected.day ? 8 : -8);
          final period = find
              .ancestor(
                of: find.byTooltip('Предыдущий период'),
                matching: find.byType(Row),
              )
              .first;
          await tester.tap(
            find.descendant(of: period, matching: find.byType(TextButton)),
          );
          await tester.pumpAndSettle();
          await pickDate(tester, next);
          selected = next;
          await expectSelected(tester, selected, view);
        }
        expect(repo.mutations, isEmpty);
      });
    }
  }
}
