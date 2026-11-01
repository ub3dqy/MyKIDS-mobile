import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/school_screen.dart';
import 'package:mykids_family/task_rewards.dart';
import 'package:mykids_family/visuals.dart';

import 'field_layout_test.dart' show revealField;
import 'support/calendar_results_fixture.dart';

class SchoolActionFixture extends ResultsFixture {
  bool queueOnly = false;
  final queued = <Map<String, Object?>>[];
  Completer<List<Map<String, Object?>>>? pendingResponse;
  SchoolActionFixture({super.role}) {
    endpoint = 'https://school-actions.invalid';
    snapshot!['schedules'] = <Map<String, dynamic>>[];
    task['financial_approval_scope'] = 'single';
  }

  Map<String, dynamic> get task =>
      (snapshot!['tasks'] as List).single as Map<String, dynamic>;

  @override
  Future<List<Map<String, Object?>>> pending() async =>
      pendingResponse == null ? queued : await pendingResponse!.future;

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) {
    if (queueOnly && path.endsWith('/submissions')) {
      changes.add({
        'path': path,
        'method': method,
        'body': Map<String, dynamic>.from(body),
        'offline': offlineSubmission,
      });
      queued.add({
        'id': 'queued-school-result-${queued.length}',
        'path': path,
        'state': 'pending',
      });
      notifyListeners();
      return Future.value({'queued': true});
    }
    if (body['action'] == 'not_completed') task['status'] = 'not_completed';
    if (body['action'] == 'approve_finances') task['financial_approved'] = 1;
    return super.mutate(
      path,
      body,
      method: method,
      offlineSubmission: offlineSubmission,
      files: files,
    );
  }

  void changeOwner(String change, {bool restore = false}) {
    final oldEndpoint = endpoint, oldToken = token;
    final oldGeneration = generation;
    final user = Map<String, dynamic>.from(snapshot!['user'] as Map);
    switch (change) {
      case 'endpoint':
        endpoint = 'https://different-school.invalid';
      case 'session':
        token = 'different-synthetic-school-session';
      case 'generation':
        generation++;
      case 'member':
        snapshot!['user']['id'] = 'another-parent';
      case 'role':
        snapshot!['user']['role'] = user['role'] == 'child'
            ? 'parent'
            : 'child';
      case 'review permission':
        snapshot!['user']['review_tasks'] = 0;
    }
    notifyListeners();
    if (restore) {
      endpoint = oldEndpoint;
      token = oldToken;
      generation = oldGeneration;
      snapshot!['user'] = user;
      notifyListeners();
    }
  }
}

Future<GlobalKey<NavigatorState>> mountSchoolActions(
  WidgetTester tester,
  SchoolActionFixture owner, {
  ValueNotifier<SchoolActionFixture>? selection,
  Future<void> Function(Future<Map<String, dynamic>> Function())? perform,
  Size size = const Size(420, 950),
  double textScale = 1,
  bool productionTheme = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    owner.client.close();
    owner.dispose();
  });
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: productionTheme ? familyTheme(false) : null,
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('school-layout-pixels'),
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: ListenableBuilder(
        listenable: Listenable.merge([owner, ?selection]),
        builder: (_, _) => SchoolScreen(
          repository: selection?.value ?? owner,
          gradesOnly: true,
          initialDay: DateTime(2026, 10, 12),
          perform:
              perform ??
              (action) async {
                await action();
              },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigator;
}

Future<void> openSchoolCompletion(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('result-complete-help'));
  await revealField(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text('Подтвердить выполнение?'), findsOneWidget);
}

VoidCallback completionCallback(WidgetTester tester, bool accept) => tester
    .widget<TextButton>(
      find.widgetWithText(TextButton, accept ? 'Выполнено' : 'Отмена'),
    )
    .onPressed!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'MyKidsNunito': 'assets/designs/Nunito.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  for (final accept in [false, true]) {
    testWidgets(
      'covered school confirmation cannot close another route: $accept',
      (tester) async {
        final repo = SchoolActionFixture();
        final navigator = await mountSchoolActions(tester, repo);
        await openSchoolCompletion(tester);
        final old = completionCallback(tester, accept);
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Другой экран семьи')),
          ),
        );
        await tester.pumpAndSettle();
        old();
        await tester.pumpAndSettle();
        expect(find.text('Другой экран семьи'), findsOneWidget);
        expect(repo.changes, isEmpty);
        expect(tester.takeException(), isNull);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        completionCallback(tester, accept)();
        await tester.pumpAndSettle();
        expect(repo.changes, hasLength(accept ? 1 : 0));
      },
    );

    testWidgets('closed school confirmation ignores its old button: $accept', (
      tester,
    ) async {
      final repo = SchoolActionFixture();
      final navigator = await mountSchoolActions(tester, repo);
      await openSchoolCompletion(tester);
      final old = completionCallback(tester, accept);
      navigator.currentState!.pop(false);
      await tester.pumpAndSettle();
      expect(old, returnsNormally);
      await tester.pumpAndSettle();
      expect(repo.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final change in ['version', 'reward', 'status', 'photo requirement']) {
    testWidgets('school completion rejects changed $change before rebuilding', (
      tester,
    ) async {
      final repo = SchoolActionFixture();
      await mountSchoolActions(tester, repo);
      await openSchoolCompletion(tester);
      final old = completionCallback(tester, true);
      switch (change) {
        case 'version':
          repo.task['version'] = 4;
        case 'reward':
          repo.task['reward'] = 170;
        case 'status':
          repo.task['status'] = 'completed';
        case 'photo requirement':
          repo.task['require_photo'] = 1;
      }
      repo.notifyListeners();
      old();
      await tester.pumpAndSettle();
      expect(repo.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final change in [
    'endpoint',
    'session',
    'generation',
    'member',
    'role',
  ]) {
    testWidgets('school decision stays revoked after restored $change', (
      tester,
    ) async {
      final repo = SchoolActionFixture();
      await mountSchoolActions(tester, repo);
      await openSchoolCompletion(tester);
      final old = completionCallback(tester, true);
      repo.changeOwner(change, restore: true);
      old();
      await tester.pumpAndSettle();
      expect(repo.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('relative school review stays revoked after permission returns', (
    tester,
  ) async {
    final repo = SchoolActionFixture(role: 'relative');
    await mountSchoolActions(tester, repo);
    await openSchoolCompletion(tester);
    final old = completionCallback(tester, true);
    repo.changeOwner('review permission', restore: true);
    old();
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('school approval shows financial terms before sending consent', (
    tester,
  ) async {
    final repo = SchoolActionFixture();
    repo.task['financial_approved'] = 0;
    await mountSchoolActions(tester, repo);
    final button = find.widgetWithText(OutlinedButton, 'Согласовать награду');
    await revealField(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    final confirmation = find.byKey(const ValueKey('confirm-task-finances'));
    expect(confirmation, findsOneWidget);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    expect(repo.changes.single['body'], {
      'action': 'approve_finances',
      'task_version': 3,
      'financial_scope': 'single',
    });
  });

  testWidgets('deferred school send cannot adopt a replacement repository', (
    tester,
  ) async {
    final repo = SchoolActionFixture(), other = SchoolActionFixture();
    final selection = ValueNotifier(repo);
    addTearDown(() {
      selection.dispose();
      other.client.close();
      other.dispose();
    });
    Future<Map<String, dynamic>> Function()? send;
    final performed = Completer<void>();
    addTearDown(() {
      if (!performed.isCompleted) performed.complete();
    });
    final caught = <Object>[];
    await mountSchoolActions(
      tester,
      repo,
      selection: selection,
      perform: (action) async {
        send = action;
        await performed.future;
      },
    );
    await openSchoolCompletion(tester);
    completionCallback(tester, true)();
    await tester.pumpAndSettle();
    expect(send, isNotNull);
    selection.value = other;
    await tester.pumpAndSettle();
    try {
      await send!();
    } catch (failure) {
      caught.add(failure);
    }
    performed.complete();
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(other.changes, isEmpty);
    expect(caught.whereType<ApiFailure>(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a repeated school confirmation submits one dated decision', (
    tester,
  ) async {
    final repo = SchoolActionFixture();
    await mountSchoolActions(tester, repo);
    await openSchoolCompletion(tester);
    final confirm = completionCallback(tester, true);
    confirm();
    confirm();
    await tester.pumpAndSettle();
    expect(repo.changes.single['body'], {
      'action': 'complete',
      'date': '2026-10-12',
      'task_version': 3,
    });
    expect(repo.task['status'], 'completed');
    expect(tester.takeException(), isNull);
  });

  for (final changed in ['unchanged', 'tier amount', 'total']) {
    testWidgets(
      'school result count stays tied to shown reward rules: $changed',
      (tester) async {
        final repo = SchoolActionFixture();
        repo.task['reward_options'] = mathRewardExample();
        await mountSchoolActions(tester, repo);
        final open = find.byKey(const ValueKey('result-complete-help'));
        await revealField(tester, open);
        await tester.tap(open);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('task-completed-count')),
          '5',
        );
        await tester.pumpAndSettle();
        expect(find.text('Начислить: 25 монет'), findsOneWidget);
        final confirm = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Подтвердить результат'),
            )
            .onPressed!;
        final options = repo.task['reward_options'] as Map;
        if (changed == 'tier amount') options['tiers'][1]['coins'] = 250;
        if (changed == 'total') options['total'] = 7;
        if (changed != 'unchanged') repo.notifyListeners();
        confirm();
        await tester.pumpAndSettle();
        if (changed == 'unchanged') {
          expect(repo.changes.single['body'], {
            'action': 'complete',
            'date': '2026-10-12',
            'task_version': 3,
            'completed_count': 5,
          });
        } else {
          expect(repo.changes, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final changed in ['unchanged', 'amount', 'version', 'owner']) {
    testWidgets(
      'school penalty keeps its occurrence and shown terms: $changed',
      (tester) async {
        final repo = SchoolActionFixture();
        repo.task.addAll({'is_required': 1, 'penalty': 500});
        await mountSchoolActions(tester, repo);
        final open = find.byKey(const ValueKey('result-not-completed-help'));
        await revealField(tester, open);
        await tester.tap(open);
        await tester.pumpAndSettle();
        final confirm = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Списать 500 монет'),
            )
            .onPressed!;
        if (changed == 'amount') repo.task['penalty'] = 700;
        if (changed == 'version') repo.task['version'] = 4;
        if (changed == 'owner') repo.changeOwner('session', restore: true);
        if (changed != 'unchanged') repo.notifyListeners();
        confirm();
        confirm();
        await tester.pumpAndSettle();
        if (changed == 'unchanged') {
          expect(repo.changes.single['path'], '/v1/tasks/help/actions');
          expect(repo.changes.single['body'], {
            'action': 'not_completed',
            'task_version': 3,
          });
          expect(repo.task['status'], 'not_completed');
        } else {
          expect(repo.changes, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final changed in ['reward', 'penalty', 'scope', 'owner']) {
    testWidgets('school financial consent rejects changed $changed', (
      tester,
    ) async {
      final repo = SchoolActionFixture();
      repo.task['financial_approved'] = 0;
      await mountSchoolActions(tester, repo);
      final open = find.widgetWithText(OutlinedButton, 'Согласовать награду');
      await revealField(tester, open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      final confirm = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-task-finances')),
          )
          .onPressed!;
      if (changed == 'reward') repo.task['reward'] = 170;
      if (changed == 'penalty') {
        repo.task.addAll({'is_required': 1, 'penalty': 500});
      }
      if (changed == 'scope') repo.task['financial_approval_scope'] = 'repeat';
      if (changed == 'owner') repo.changeOwner('member', restore: true);
      repo.notifyListeners();
      confirm();
      await tester.pumpAndSettle();
      expect(repo.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final role in ['parent', 'relative']) {
    testWidgets('offline $role is told why school review is unavailable', (
      tester,
    ) async {
      final repo = SchoolActionFixture(role: role)..online = false;
      await mountSchoolActions(tester, repo);
      final complete = find.byKey(const ValueKey('result-complete-help'));
      await revealField(tester, complete);
      expect(tester.widget<FilledButton>(complete).onPressed, isNull);
      await revealField(tester, find.textContaining('Для '));
      expect(
        find.textContaining('подтверждения заданий нужен интернет'),
        findsOneWidget,
      );
      expect(repo.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final online in [true, false]) {
    testWidgets('child school submission preserves offline support: $online', (
      tester,
    ) async {
      final repo = SchoolActionFixture(role: 'child')..online = online;
      await mountSchoolActions(tester, repo);
      final submit = find.byKey(const ValueKey('result-submit-help'));
      await revealField(tester, submit);
      final send = tester.widget<FilledButton>(submit).onPressed!;
      send();
      send();
      await tester.pumpAndSettle();
      expect(repo.changes.single['path'], '/v1/tasks/help/submissions');
      expect(repo.changes.single['offline'], isTrue);
      expect(repo.changes.single['body']['task_version'], 3);
      expect(
        DateTime.parse(repo.changes.single['body']['marked_at']).isUtc,
        isTrue,
      );
      expect(repo.task['status'], 'submitted');
      expect(tester.takeException(), isNull);
    });
  }

  for (final changed in ['version', 'owner', 'day', 'covered', 'disposed']) {
    testWidgets('old child school button cannot send after $changed', (
      tester,
    ) async {
      final repo = SchoolActionFixture(role: 'child');
      final navigator = await mountSchoolActions(tester, repo);
      final submit = find.byKey(const ValueKey('result-submit-help'));
      await revealField(tester, submit);
      final send = tester.widget<FilledButton>(submit).onPressed!;
      if (changed == 'version') repo.task['version'] = 4;
      if (changed == 'owner') repo.changeOwner('role', restore: true);
      if (changed == 'day') {
        await tester.tap(find.byTooltip('Следующий день'));
        await tester.pumpAndSettle();
      }
      if (changed == 'covered') {
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Другой экран семьи')),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (changed == 'disposed') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      send();
      await tester.pumpAndSettle();
      expect(repo.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('deferred school send cannot run under another screen', (
    tester,
  ) async {
    final repo = SchoolActionFixture();
    final performed = Completer<void>();
    addTearDown(() {
      if (!performed.isCompleted) performed.complete();
    });
    Future<Map<String, dynamic>> Function()? send;
    final navigator = await mountSchoolActions(
      tester,
      repo,
      perform: (action) async {
        send = action;
        await performed.future;
      },
    );
    await openSchoolCompletion(tester);
    completionCallback(tester, true)();
    await tester.pumpAndSettle();
    expect(send, isNotNull);
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Другой экран семьи')),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(Future.sync(send!), throwsA(isA<ApiFailure>()));
    performed.complete();
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(find.text('Другой экран семьи'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'queued school result is not duplicated in a fresh calendar page',
    (tester) async {
      final repo = SchoolActionFixture(role: 'child')
        ..online = false
        ..queueOnly = true;
      final failures = <ApiFailure>[];
      Future<void> perform(
        Future<Map<String, dynamic>> Function() action,
      ) async {
        try {
          await action();
        } on ApiFailure catch (failure) {
          failures.add(failure);
        }
      }

      final navigator = await mountSchoolActions(
        tester,
        repo,
        perform: perform,
      );
      final submit = find.byKey(const ValueKey('result-submit-help'));
      await revealField(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repo.changes, hasLength(1));
      expect(
        repo.task['status'],
        'assigned',
        reason: 'The durable queue does not rewrite the server snapshot.',
      );
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SchoolScreen(
            repository: repo,
            gradesOnly: true,
            initialDay: DateTime(2026, 10, 12),
            perform: perform,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await revealField(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repo.changes, hasLength(1));
      expect(repo.queued, hasLength(1));
      expect(failures.single.message, contains('сохранён'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final existing in ['other task', 'failed attempt']) {
    testWidgets('school submission is not blocked by an $existing', (
      tester,
    ) async {
      final repo = SchoolActionFixture(role: 'child');
      repo.queued.add({
        'path': existing == 'other task'
            ? '/v1/tasks/other/submissions'
            : '/v1/tasks/help/submissions',
        'state': existing == 'other task' ? 'pending' : 'failed',
      });
      await mountSchoolActions(tester, repo);
      final submit = find.byKey(const ValueKey('result-submit-help'));
      await revealField(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repo.changes.single['path'], '/v1/tasks/help/submissions');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending school lookup cannot submit after its owner changes', (
    tester,
  ) async {
    final repo = SchoolActionFixture(role: 'child');
    repo.pendingResponse = Completer<List<Map<String, Object?>>>();
    addTearDown(() {
      if (!repo.pendingResponse!.isCompleted) {
        repo.pendingResponse!.complete([]);
      }
    });
    final failures = <Object>[];
    await mountSchoolActions(
      tester,
      repo,
      perform: (action) async {
        try {
          await action();
        } catch (failure) {
          failures.add(failure);
        }
      },
    );
    final submit = find.byKey(const ValueKey('result-submit-help'));
    await revealField(tester, submit);
    await tester.tap(submit);
    await tester.pump();
    repo.changeOwner('member', restore: true);
    repo.pendingResponse!.complete([]);
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(failures.whereType<ApiFailure>(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final design in GameDesign.all) {
    for (final landscape in [false, true]) {
      testWidgets(
        'school result remains usable with large text: ${design.id}, landscape=$landscape',
        (tester) async {
          final previous = gameDesign.value;
          gameDesign.value = design;
          addTearDown(() => gameDesign.value = previous);
          final repo = SchoolActionFixture();
          repo.task['title'] = 'Проверить все задачи космической экспедиции с Лучиком и роботами';
          repo.task['reward_options'] = mathRewardExample();
          await mountSchoolActions(
            tester,
            repo,
            size: landscape ? const Size(780, 360) : const Size(320, 640),
            textScale: landscape ? 1.5 : 2,
            productionTheme: true,
          );
          final open = find.byKey(const ValueKey('result-complete-help'));
          await revealField(tester, open);
          await tester.tap(open);
          await tester.pumpAndSettle();
          final input = find.byKey(const ValueKey('task-completed-count'));
          await tester.ensureVisible(input);
          await tester.enterText(input, '5');
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
          final confirm = find.widgetWithText(
            FilledButton,
            'Подтвердить результат',
          );
          await tester.ensureVisible(confirm);
          await tester.pumpAndSettle();
          const evidence = String.fromEnvironment(
            'MYKIDS_SCHOOL_LAYOUT_EVIDENCE',
          );
          if (evidence.isNotEmpty) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('school-layout-pixels')),
              );
              final image = await boundary.toImage();
              try {
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final directory = Directory(evidence)
                  ..createSync(recursive: true);
                await File(
                  '${directory.path}/${design.id}-${landscape ? 'landscape' : 'portrait'}.png',
                ).writeAsBytes(data!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
          final label = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: confirm,
              matching: find.text('Подтвердить результат'),
            ),
          );
          expect(
            label.getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 11),
            ),
            hasLength(1),
            reason: 'The confirmation verb must not split inside a word.',
          );
          await tester.tap(confirm);
          await tester.pumpAndSettle();
          expect(repo.changes.single['body']['completed_count'], 5);
          expect(repo.changes.single['body']['date'], '2026-10-12');
          expect(repo.task['status'], 'completed');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
