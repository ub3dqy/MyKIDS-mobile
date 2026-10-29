import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/updates.dart';

import 'unread_badge_test.dart'
    show
        ReadFixture,
        showReadChat,
        settleReads,
        resumeReadApp,
        closeReadFixture;

class NoResumeUpdates extends AppUpdates {
  @override
  Future<UpdateOffer?> check(Uri base, String role) async => null;
}

class ResumeBackground extends BackgroundServices {
  Completer<void>? initialization;
  int alarms = 0, registrations = 0;
  ResumeBackground(super.repository);
  @override
  Future<void> initialize(void Function(String?) onTap) async {
    await initialization?.future;
  }

  @override
  Future<void> checkCallPermissions() async {}
  @override
  Future<void> reminders() async {
    alarms++;
  }

  @override
  Future<void> registerDevice() async {
    registrations++;
  }
}

class ResumeFixture extends FamilyRepository {
  int syncs = 0, resumes = 0;
  Completer<void>? waitResume;
  ResumeFixture(String role) {
    token = 'synthetic-resume-$role';
    endpoint = 'https://family.example';
    online = true;
    snapshot = {
      'user': {'id': role, 'role': role, 'name': 'Проверка'},
      'family': {'timezone': 'Europe/Moscow'},
      'balance': {'total': 10, 'reserved': 0, 'available': 10},
      'members': [],
      'tasks': [],
      'rooms': [],
      'schedules': [],
      'schedule_exceptions': [],
      'grades': [],
      'rewards': [],
      'goal': null,
      'penalties': [],
      'redemptions': [],
      'ledger': [],
      'audit': [],
    };
  }
  @override
  Future<void> sync() async {
    syncs++;
  }

  @override
  Future<void> reconnect() async {
    resumes++;
    final identity = sessionTag;
    await waitResume?.future;
    if (identity != sessionTag) return;
    snapshot!['balance'] = {'total': 60, 'reserved': 5, 'available': 55};
    notifyListeners();
  }

  @override
  Future<List<Map<String, Object?>>> pending() async => [];
}

void pauseResumeApp(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

class HeldReadFixture extends ReadFixture {
  int loads = 0;
  Completer<Map<String, dynamic>>? nextLoad;
  HeldReadFixture() : super(count: 1, longMessages: true);
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) {
    if (path.endsWith('/messages')) {
      loads++;
      final held = nextLoad;
      nextLoad = null;
      if (held != null) return held.future;
    }
    return super.request(
      path,
      method: method,
      body: body,
      key: key,
      query: query,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<ResumeBackground> open(
    WidgetTester tester,
    ResumeFixture repo, {
    Completer<void>? initialization,
  }) async {
    resumeReadApp(tester);
    final background = ResumeBackground(repo)..initialization = initialization;
    await tester.pumpWidget(
      MyKidsApp(
        repository: repo,
        createBackground: (_) => background,
        createUpdates: NoResumeUpdates.new,
        now: () => DateTime.utc(2026, 10, 16, 12),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      if (initialization != null && !initialization.isCompleted) {
        initialization.complete();
      }
      if (repo.waitResume != null && !repo.waitResume!.isCompleted) {
        repo.waitResume!.complete();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
      resumeReadApp(tester);
    });
    return background;
  }

  for (final actor in ['kid', 'papa', 'mama']) {
    final role = actor == 'kid' ? 'child' : 'parent';
    testWidgets(
      '$actor resumes into a fresh refresh and updates the open money screen',
      (tester) async {
        final repo = ResumeFixture(role);
        await open(tester, repo);
        await tester.tap(find.text('Монеты').last);
        await tester.pumpAndSettle();
        for (final cycle in [1, 2]) {
          repo.snapshot!['balance'] = {
            'total': 10,
            'reserved': 0,
            'available': 10,
          };
          pauseResumeApp(tester);
          final before = repo.syncs;
          await tester.pump(const Duration(seconds: 10));
          expect(repo.syncs, before);
          resumeReadApp(tester);
          await tester.pumpAndSettle();
          expect(repo.resumes, cycle);
          expect(repo.snapshot!['balance']['available'], 55);
          expect(find.textContaining('Всего: 60'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'late initialization cannot restart periodic updates while paused',
    (tester) async {
      final gate = Completer<void>();
      final repo = ResumeFixture('parent');
      await open(tester, repo, initialization: gate);
      pauseResumeApp(tester);
      gate.complete();
      await tester.pump();
      final before = repo.syncs;
      await tester.pump(const Duration(seconds: 12));
      expect(repo.syncs, before);
      resumeReadApp(tester);
      await tester.pumpAndSettle();
      expect(repo.resumes, 1);
    },
  );
  for (final end in ['dispose', 'new account']) {
    testWidgets(
      '$end while returning prevents stale reminder and device work',
      (tester) async {
        final repo = ResumeFixture('parent');
        final background = await open(tester, repo);
        pauseResumeApp(tester);
        repo.waitResume = Completer<void>();
        final alarms = background.alarms,
            registrations = background.registrations;
        resumeReadApp(tester);
        await tester.pump();
        if (end == 'dispose') {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          repo.token = 'another-account';
          repo.generation++;
        }
        repo.waitResume!.complete();
        await tester.pumpAndSettle();
        expect(background.alarms, alarms);
        expect(background.registrations, registrations);
      },
    );
  }
  testWidgets(
    'chat pauses polling and loads unread messages immediately after unlock',
    (tester) async {
      final repo = HeldReadFixture();
      closeReadFixture(tester, repo);
      await showReadChat(tester, repo);
      await settleReads(tester);
      pauseResumeApp(tester);
      final before = repo.loads;
      repo.addIncoming('while-locked', longMessages: true);
      await tester.pump(const Duration(seconds: 12));
      expect(repo.loads, before);
      expect(repo.unread, 1);
      resumeReadApp(tester);
      await settleReads(tester);
      expect(repo.loads, before + 1);
      expect(find.textContaining('while-locked'), findsOneWidget);
      expect(repo.unread, 0);
    },
  );
  for (final failure in [false, true]) {
    testWidgets(
      'old chat load ${failure ? 'fails' : 'returns'} after unlock without blocking a fresh load',
      (tester) async {
        final repo = HeldReadFixture();
        closeReadFixture(tester, repo);
        await showReadChat(tester, repo);
        await settleReads(tester);
        final old = Completer<Map<String, dynamic>>();
        repo.nextLoad = old;
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        final before = repo.loads;
        pauseResumeApp(tester);
        repo.addIncoming('new-after-lock', longMessages: true);
        resumeReadApp(tester);
        if (failure) {
          old.completeError(Exception('Old connection closed'));
        } else {
          old.complete({'messages': [], 'has_more': false});
        }
        await settleReads(tester);
        expect(repo.loads, before + 1);
        expect(find.textContaining('new-after-lock'), findsOneWidget);
        expect(find.text('Для семейного чата нужен интернет'), findsNothing);
        expect(repo.unread, 0);
      },
    );
  }
  testWidgets(
    'account change during pause prevents chat reload under the old reader',
    (tester) async {
      final repo = HeldReadFixture();
      closeReadFixture(tester, repo);
      await showReadChat(tester, repo);
      await settleReads(tester);
      pauseResumeApp(tester);
      final before = repo.loads;
      repo.token = 'new-account';
      repo.generation++;
      resumeReadApp(tester);
      await settleReads(tester);
      expect(repo.loads, before);
    },
  );
  testWidgets('disposed chat never reloads when the application resumes', (
    tester,
  ) async {
    final repo = HeldReadFixture();
    closeReadFixture(tester, repo);
    await showReadChat(tester, repo);
    await settleReads(tester);
    final before = repo.loads;
    await tester.pumpWidget(const SizedBox.shrink());
    pauseResumeApp(tester);
    resumeReadApp(tester);
    await tester.pump();
    expect(repo.loads, before);
  });
}
