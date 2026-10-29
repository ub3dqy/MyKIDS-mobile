import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/morning.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/updates.dart';
import 'package:mykids_family/visuals.dart';

class CalendarQuietUpdates extends AppUpdates {
  @override
  Future<UpdateOffer?> check(Uri url, String role) async => null;
}

class CalendarFixture extends FamilyRepository {
  CalendarFixture()
    : super(client: MockClient((_) async => http.Response('{}', 200))) {
    token = 'synthetic-calendar-unregistered';
    variant = 'child';
    online = true;
    Map<String, dynamic> e(
      String id,
      String title,
      String start,
      String end,
      String kind,
    ) => {
      'id': id,
      'title': title,
      'date': '2026-10-12',
      'weekdays': '[]',
      'start': start,
      'end': end,
      'kind': kind,
      'reminder_minutes': 30,
      'active': 1,
    };
    snapshot = {
      'user': {
        'id': 'native-calendar-child',
        'name': 'Проверочный ребёнок',
        'role': 'child',
      },
      'family': {
        'timezone': 'Europe/Moscow',
        'quiet_start': '00:00',
        'quiet_end': '00:00',
        'day_start': '07:00',
        'day_end': '22:00',
      },
      'server_time': '2026-10-12T04:30:00Z',
      'balance': {'available': 0},
      'members': [
        {'id': 'father', 'name': 'Папа'},
      ],
      'schedules': [
        e('math', 'Математика', '08:30', '09:15', 'school'),
        e('literature', 'Литература', '09:25', '10:10', 'school'),
        e('chess', 'Шахматы', '15:00', '16:00', 'extra'),
        e('music', 'Сольфеджио', '17:00', '18:00', 'extra'),
      ],
      'tasks': [
        {
          'id': 'code',
          'title': 'Программирование с папой',
          'description': 'Проверочное задание',
          'author_id': 'father',
          'status': 'assigned',
          'due_at': '2026-10-12T19:00:00Z',
          'planned_start': '2026-10-12T17:30:00Z',
          'planned_end': '2026-10-12T18:30:00Z',
          'reminder_minutes': 30,
          'reward': 0,
          'penalty': 0,
        },
      ],
      'ledger': <Map<String, dynamic>>[],
      'schedule_exceptions': <Map<String, dynamic>>[],
    };
  }
  @override
  Future<void> sync() async {}
  @override
  Future<List<Map<String, Object?>>> pending() async => [];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native calendar, authored animation, daily overview and reminder registration',
    (tester) async {
      final repo = CalendarFixture();
      await repo.storage.delete(key: 'morning:native-calendar-child');
      var now = DateTime.utc(2026, 10, 12, 4, 30);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpWidget(
        MyKidsApp(
          repository: repo,
          createUpdates: CalendarQuietUpdates.new,
          now: () => now,
        ),
      );
      await tester.runAsync(
        () => precacheFamilyArtwork(tester.element(find.byType(MyKidsApp))),
      );
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        await settle();
        for (var attempt = 0; attempt < 40; attempt++) {
          final ready = find
              .byType(RasterSprite)
              .evaluate()
              .every(
                (s) => find
                    .descendant(
                      of: find.byWidget(s.widget),
                      matching: find.byType(CustomPaint),
                    )
                    .evaluate()
                    .isNotEmpty,
              );
          if (ready) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(tester.takeException(), isNull);
        var complete = false;
        final pending = binding.takeScreenshot(name);
        pending.whenComplete(() => complete = true).ignore();
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (!complete && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
        }
        if (!complete) throw StateError('Calendar screenshot timeout: $name');
        await pending;
      }

      await settle();
      expect(find.byType(MorningOverview), findsOneWidget);
      expect(find.text('Сегодня школа'), findsOneWidget);
      expect(find.text('Математика, Литература'), findsOneWidget);
      final initial = tester
          .widget<RasterSprite>(
            find.descendant(
              of: find.byType(CalendarMotion),
              matching: find.byType(RasterSprite),
            ),
          )
          .source;
      var changedFrame = false;
      for (var attempt = 0; attempt < 16; attempt++) {
        await tester.pump(const Duration(milliseconds: 320));
        final frame = tester
            .widget<RasterSprite>(
              find.descendant(
                of: find.byType(CalendarMotion),
                matching: find.byType(RasterSprite),
              ),
            )
            .source;
        if (frame != initial) {
          changedFrame = true;
          break;
        }
      }
      expect(changedFrame, true);
      await capture('calendar-morning-school');
      await tester.tap(find.text('Дальше'));
      await settle();
      expect(find.text('Шахматы'), findsOneWidget);
      await capture('calendar-morning-extra');
      final taskTitle = find.descendant(
        of: find.byType(MorningOverview),
        matching: find.text('Программирование с папой'),
      );
      for (var i = 0; i < 10 && taskTitle.evaluate().isEmpty; i++) {
        await tester.tap(find.text('Дальше'));
        await settle();
      }
      expect(taskTitle, findsOneWidget);
      expect(
        tester
            .widget<RasterSprite>(
              find.descendant(
                of: find.byType(CalendarMotion),
                matching: find.byType(RasterSprite),
              ),
            )
            .path,
        'assets/generated/calendar-task.png',
      );
      await capture('calendar-morning-task');
      await tester.tap(find.text('Весь день'));
      await settle();
      expect(find.byType(CalendarScreen), findsOneWidget);
      await capture('calendar-day');
      for (final view in ['Неделя', 'Месяц']) {
        await tester.tap(find.widgetWithText(ChoiceChip, view));
        await settle();
        await capture('calendar-${view == 'Неделя' ? 'week' : 'month'}');
      }
      await tester.tap(find.text('Сегодня').last);
      await settle();
      repo.notifyListeners();
      await settle();
      expect(find.byType(MorningOverview), findsNothing);
      now = DateTime.utc(2026, 10, 13, 4, 30);
      repo.notifyListeners();
      await settle();
      expect(find.byType(MorningOverview), findsOneWidget);
      await tester.tap(find.text('Понятно!'));
      await settle();
      await tester.pumpWidget(const SizedBox.shrink());
      await initializeNotifications();
      await notifications.cancelAll();
      final services = BackgroundServices(repo);
      // Reminder assertions use a future civil day, independently of the
      // fixed date used for morning screenshots.
      final tomorrow = familyClock(
        repo.snapshot,
        DateTime.now(),
      ).add(const Duration(days: 1));
      for (final item in repo.rows('schedules')) {
        final original = (repo.snapshot!['schedules'] as List).firstWhere(
          (row) => row['id'] == item['id'],
        );
        original['date'] = dateOnly(tomorrow);
      }
      await services.reminders();
      final first = await notifications.pendingNotificationRequests();
      final expected = calendarReminders(repo.snapshot!, DateTime.now());
      expect(expected, isNotEmpty);
      expect(first.length, expected.length);
      expect(
        first.every((n) => n.payload?.startsWith('calendar:') == true),
        true,
      );
      await services.reminders();
      final repeated = await notifications.pendingNotificationRequests();
      expect(repeated.map((n) => n.id).toSet(), first.map((n) => n.id).toSet());
      (repo.snapshot!['schedules'] as List).clear();
      await services.reminders();
      final removed = await notifications.pendingNotificationRequests();
      expect(removed.length, lessThan(first.length));
      repo.token = null;
      await services.reminders();
      expect(await notifications.pendingNotificationRequests(), isEmpty);
      services.dispose();
      await repo.storage.delete(key: 'morning:native-calendar-child');
      repo.client.close();
      repo.dispose();
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'all_three_periods_rendered': true,
        'authored_frames_change': true,
        'school_subjects_grouped': true,
        'morning_once_daily': true,
        'next_day_overview': true,
        'native_reminders_registered': true,
        'reminder_cancellation_verified': true,
        'physical_phones_tested': false,
        'alarm_delivery_timing_tested': false,
      };
    },
  );
}
