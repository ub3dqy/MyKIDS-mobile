import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/calendar_position.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'calendar_creation_date_test.dart' show pickDate;
import 'calendar_keep_date_test.dart' show KeepDateBackground, expectSelected;
import 'calendar_removal_date_test.dart' show chosenDay;
import 'resume_refresh_test.dart' show NoResumeUpdates;
import 'support/owned_temp.dart';

class RestartRepository extends FamilyRepository {
  final FlutterSecureStorage controlled;
  RestartRepository({
    this.controlled = const FlutterSecureStorage(),
    super.client,
  });
  @override
  FlutterSecureStorage get storage => controlled;
  @override
  Future<void> sync() async => notifyListeners();
  @override
  Future<void> reconnect() => sync();
}

class WidgetRestartRepository extends RestartRepository {
  WidgetRestartRepository({super.client});
  @override
  Future<void> guardDeviceUpdate(Future<void> Function() action) => action();
  @override
  Future<List<Map<String, Object?>>> pending() async => [];
}

class HeldCalendarStorage extends FlutterSecureStorage {
  final started = Completer<void>(), release = Completer<void>();
  int writes = 0;
  bool failFirst = false, failRead = false;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == CalendarPosition.storageKey && failRead) {
      throw PlatformException(code: 'synthetic-preference-read');
    }
    return super.read(key: key);
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == CalendarPosition.storageKey && writes++ == 0) {
      started.complete();
      await release.future;
      if (failFirst) {
        throw PlatformException(code: 'synthetic-preference-write');
      }
    }
    await super.write(key: key, value: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory folder;
  final repos = <RestartRepository>[];
  final held = <HeldCalendarStorage>[];
  WidgetTester? activeTester;
  bool cleaned = false;
  var process = 'before-close';
  Map<String, dynamic> data(String role, {String zone = 'Europe/Moscow'}) => {
    'server_time': 'synthetic',
    'user': {'id': role, 'name': 'Проверка', 'role': role},
    'family': {'timezone': zone},
    'balance': {'total': 20, 'available': 20, 'reserved': 0},
    'members': [],
    'tasks': [],
    'schedules': [],
    'schedule_exceptions': [],
  };
  setUp(() async {
    activeTester = null;
    cleaned = false;
    folder = await Directory.systemTemp.createTemp('mykids-calendar-restart-');
    await databaseFactory.setDatabasesPath(folder.path);
    process = 'before-close';
    FlutterSecureStorage.setMockInitialValues({
      'session': 'synthetic-calendar-restart',
      'endpoint': 'https://family.example',
      'morning:child': dateOnly(familyClock(null)),
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('ru.mykids/runtime'),
      (_) async => process,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => folder.path,
    );
  });
  Future<void> cleanup() async {
    if (cleaned) return;
    for (final storage in held) {
      if (!storage.release.isCompleted) storage.release.complete();
    }
    held.clear();
    for (final repo in repos) {
      await repo.flushCalendarPosition();
      if (repo.db?.isOpen == true) await repo.db!.close();
      repo.client.close();
      repo.dispose();
    }
    repos.clear();
    final resolved = p.normalize(folder.absolute.path);
    expect(p.isWithin(Directory.systemTemp.absolute.path, resolved), true);
    expect(p.basename(resolved).startsWith('mykids-calendar-restart-'), true);
    await deleteOwnedTestTemp(folder);
    expect(await folder.exists(), false);
    cleaned = true;
  }

  tearDown(() async {
    if (cleaned) return;
    final tester = activeTester;
    if (tester != null && tester.binding.inTest) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(cleanup);
    } else {
      await cleanup();
    }
  });
  Future<RestartRepository> open({HeldCalendarStorage? storage}) async {
    if (storage != null) held.add(storage);
    final client = MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          jsonEncode(
            request.url.path == '/v1/login'
                ? {'token': 'another-calendar-session'}
                : data('parent'),
          ),
        ),
        200,
      ),
    );
    final repo = RestartRepository(
      controlled: storage ?? const FlutterSecureStorage(),
      client: client,
    );
    repos.add(repo);
    await repo.initialize();
    return repo;
  }

  Future<void> seed(
    RestartRepository repo,
    String role, {
    String zone = 'Europe/Moscow',
  }) async {
    await repo.db!.insert('identity', {
      'id': 1,
      'tag': repo.sessionTag,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    repo.snapshot = data(role, zone: zone);
    await repo.cache(repo.snapshot!);
  }

  Future<RestartRepository> openWidget(WidgetTester tester) async {
    // Construct in the widget zone; only the real database I/O leaves it.
    final repo = WidgetRestartRepository(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    repos.add(repo);
    await tester.runAsync(repo.initialize);
    return repo;
  }

  Future<KeepDateBackground> showApp(
    WidgetTester tester,
    RestartRepository repo,
  ) async {
    final background = KeepDateBackground(repo);
    await tester.pumpWidget(
      MyKidsApp(
        repository: repo,
        createBackground: (_) => background,
        createUpdates: NoResumeUpdates.new,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Календарь').last);
    await tester.pumpAndSettle();
    return background;
  }

  Future<void> selectDay(WidgetTester tester, DateTime day) async {
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
    await pickDate(tester, day);
  }

  void resize(WidgetTester tester) {
    activeTester = tester;
    tester.view.physicalSize = const Size(440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  }

  for (final role in ['parent', 'child', 'relative']) {
    for (final view in ['День', 'Неделя', 'Месяц']) {
      for (final offset in [-8, 8]) {
        testWidgets('$role $view survives a full restart with date $offset', (
          tester,
        ) async {
          resize(tester);
          final before = await openWidget(tester);
          await tester.runAsync(() => seed(before, role));
          final selected = chosenDay(offset);
          await showApp(tester, before);
          await selectDay(tester, selected);
          await tester.tap(find.widgetWithText(ChoiceChip, view));
          await tester.pumpAndSettle();
          await tester.runAsync(before.flushCalendarPosition);
          if (offset > 0) {
            await tester.tap(find.byTooltip('Настройки'));
            await tester.pumpAndSettle();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() => before.db!.close());
          process = 'fresh-process-after-close';
          final after = await openWidget(tester);
          expect(
            after.calendarPosition?.day,
            DateTime.utc(selected.year, selected.month, selected.day),
          );
          expect(after.calendarPosition?.mode, view);
          expect(after.snapshot, data(role));
          expect(after.online, false);
          await showApp(tester, after);
          await expectSelected(tester, selected, view);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(cleanup);
        });
      }
    }
  }

  for (final zone in ['America/Los_Angeles', 'Pacific/Kiritimati']) {
    test(
      'cold restore keeps the civil date after timezone changes to $zone',
      () async {
        final before = await open();
        await seed(before, 'parent');
        await before.saveCalendarPosition(DateTime.utc(2026, 10, 12), 'Месяц');
        await seed(before, 'parent', zone: zone);
        await before.db!.close();
        final after = await open();
        expect(after.calendarPosition?.day, DateTime.utc(2026, 10, 12));
        expect(after.calendarPosition?.mode, 'Месяц');
        expect(after.snapshot?['family']['timezone'], zone);
      },
    );
  }

  final corrupt = <Object?>[
    null,
    'not-json',
    [],
    '{}',
    {'version': 2},
    {'mode': 'Year'},
    {'date': '2026-02-30'},
    {'date': '2026-13-01'},
    {'date': '2026-00-12'},
    {'date': '0000-01-01'},
    {'date': '2026-10-12T00:00:00Z'},
    {'mode': 3},
    {'endpoint': 'https://other.example'},
    {'session_tag': 'other-family'},
  ];
  for (var i = 0; i < corrupt.length; i++) {
    test(
      'invalid or foreign saved calendar $i does not affect login or cached data',
      () async {
        final before = await open();
        await seed(before, 'parent');
        final item = corrupt[i];
        final encoded = item is Map
            ? jsonEncode({
                'version': 1,
                'endpoint': before.endpoint,
                'session_tag': before.sessionTag,
                'date': '2026-10-12',
                'mode': 'Неделя',
                ...item,
              })
            : item is String
            ? item
            : jsonEncode(item);
        await before.storage.write(
          key: CalendarPosition.storageKey,
          value: encoded,
        );
        await before.db!.close();
        final after = await open();
        expect(after.calendarPosition, isNull);
        expect(after.token, 'synthetic-calendar-restart');
        expect(after.snapshot, data('parent'));
      },
    );
  }

  test('rapid choices persist the newest date in write order', () async {
    final storage = HeldCalendarStorage();
    final repo = await open(storage: storage);
    await seed(repo, 'parent');
    final first = repo.saveCalendarPosition(DateTime(2026, 10, 12), 'День');
    await storage.started.future;
    final last = repo.saveCalendarPosition(DateTime(2026, 11, 20), 'Месяц');
    expect(storage.writes, 1);
    storage.release.complete();
    await Future.wait([first, last]);
    await repo.db!.close();
    final after = await open();
    expect(after.calendarPosition?.day, DateTime.utc(2026, 11, 20));
    expect(after.calendarPosition?.mode, 'Месяц');
  });

  test(
    'a failed preference write can be retried without losing family data',
    () async {
      final storage = HeldCalendarStorage()..failFirst = true;
      storage.release.complete();
      final repo = await open(storage: storage);
      await seed(repo, 'parent');
      await expectLater(
        repo.saveCalendarPosition(DateTime(2026, 10, 12), 'День'),
        throwsA(isA<PlatformException>()),
      );
      await repo.saveCalendarPosition(DateTime(2026, 10, 20), 'Неделя');
      await repo.db!.close();
      final after = await open();
      expect(after.calendarPosition?.day, DateTime.utc(2026, 10, 20));
      expect(after.snapshot, data('parent'));
    },
  );

  test('a preference read failure does not block a saved login', () async {
    final before = await open();
    await seed(before, 'parent');
    await before.db!.close();
    final after = await open(storage: HeldCalendarStorage()..failRead = true);
    expect(after.calendarPosition, isNull);
    expect(after.signedIn, true);
    expect(after.snapshot, data('parent'));
  });

  test('logout clears a pending choice and queued older choices', () async {
    final storage = HeldCalendarStorage();
    final repo = await open(storage: storage);
    await seed(repo, 'parent');
    final first = repo.saveCalendarPosition(DateTime(2026, 10, 12), 'День');
    await storage.started.future;
    final queued = repo.saveCalendarPosition(DateTime(2026, 10, 20), 'Месяц');
    final leaving = repo.logout(remote: false);
    storage.release.complete();
    await Future.wait([first, queued, leaving]);
    expect(await repo.storage.read(key: CalendarPosition.storageKey), isNull);
    expect(repo.calendarPosition, isNull);
    expect(repo.signedIn, false);
    await repo.login('https://family.example', 'another', 'synthetic-password');
    expect(repo.calendarPosition, isNull);
    await repo.saveCalendarPosition(DateTime(2026, 11, 20), 'Неделя');
    await repo.db!.close();
    final after = await open();
    expect(after.calendarPosition?.day, DateTime.utc(2026, 11, 20));
  });

  test(
    'an old background session cannot replace the new account calendar',
    () async {
      final old = await open();
      await seed(old, 'parent');
      final current = await open();
      await current.login(
        'https://family.example',
        'another',
        'synthetic-password',
      );
      await current.saveCalendarPosition(DateTime(2026, 11, 20), 'Месяц');
      final saved = await current.storage.read(
        key: CalendarPosition.storageKey,
      );
      await old.saveCalendarPosition(DateTime(2026, 10, 12), 'День');
      expect(
        await current.storage.read(key: CalendarPosition.storageKey),
        saved,
      );
      expect(old.calendarPosition, isNotNull);
      await current.db!.close();
      final reopened = await open();
      expect(reopened.calendarPosition?.day, DateTime.utc(2026, 11, 20));
    },
  );

  for (final notification in [false, true]) {
    testWidgets(
      'explicit ${notification ? 'notification' : 'Today'} date replaces the saved selection',
      (tester) async {
        resize(tester);
        final before = await openWidget(tester);
        await tester.runAsync(() => seed(before, 'parent'));
        final background = await showApp(tester, before);
        await selectDay(tester, chosenDay(-8));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Месяц'));
        await tester.pumpAndSettle();
        final selected = notification
            ? DateTime.utc(2026, 10, 12)
            : familyClock(before.snapshot);
        if (notification) {
          background.openNotification!('calendar:2026-10-12|event:test');
        } else {
          await tester.tap(find.text('Сегодня').first);
        }
        await tester.pumpAndSettle();
        await tester.runAsync(before.flushCalendarPosition);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => before.db!.close());
        final after = await openWidget(tester);
        await showApp(tester, after);
        await expectSelected(tester, selected, notification ? 'День' : 'Месяц');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(cleanup);
      },
    );
  }
}
