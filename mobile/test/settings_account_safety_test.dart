import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/assistant_settings.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/settings_screen.dart';

import 'settings_safety_test.dart' show SettingsRepository;

class AccountSettingsFixture extends SettingsRepository {
  Completer<Map<String, dynamic>>? reply;
  bool failRefresh = false;
  final commands = <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> pending() async => commands;

  @override
  Future<void> sync() async {
    if (failRefresh) throw ApiFailure(503, 'Проверочная ошибка связи');
    notifyListeners();
  }

  AccountSettingsFixture() {
    endpoint = 'https://synthetic.invalid';
    snapshot!['assistant_rules'] = [
      {
        'id': 'private-rule',
        'title': 'Личное правило первой семьи',
        'keywords': ['регби'],
        'message': 'Личные приготовления первой семьи',
        'minutes_before': 45,
        'enabled': true,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    changes.add({
      'path': path,
      'method': method,
      'body': Map<String, dynamic>.from(body),
      'user': userId,
      'generation': generation,
    });
    return reply == null ? {'ok': true} : reply!.future;
  }
}

Future<void> mountAccountSettings(
  WidgetTester tester,
  AccountSettingsFixture repo, {
  bool assistant = false,
  ValueNotifier<AccountSettingsFixture>? selection,
  double scale = 1,
  Future<void> Function(Future<Map<String, dynamic>> Function())? perform,
}) async {
  final background = BackgroundServices(repo);
  tester.view.physicalSize = const Size(400, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    if (repo.reply?.isCompleted == false) repo.reply!.complete({'ok': true});
    await tester.pumpWidget(const SizedBox.shrink());
    background.dispose();
    repo.client.close();
    repo.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: ListenableBuilder(
        listenable: Listenable.merge([repo, ?selection]),
        builder: (_, _) => assistant
            ? AssistantSettings(repository: selection?.value ?? repo)
            : Scaffold(
                body: SettingsScreen(
                  repository: selection?.value ?? repo,
                  background: background,
                  perform:
                      perform ??
                      (action) async {
                        await action();
                      },
                  onUpdates: () async {},
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openAccountForm(WidgetTester tester, bool assistant) async {
  final button = find.text(
    assistant ? 'Личное правило первой семьи' : 'Часовой пояс и тихие часы',
  );
  await tester.scrollUntilVisible(
    button,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(FamilyForm), findsOneWidget);
}

Future<void> saveAccountForm(WidgetTester tester) async {
  final button = find.text('Сохранить');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final assistant in [false, true]) {
    final section = assistant ? 'assistant' : 'quiet hours';
    for (final change in [
      'account',
      'server',
      'generation',
      'role',
      'restored role',
    ]) {
      testWidgets(
        '$section rejects an old Save callback after $change changes',
        (tester) async {
          final repo = AccountSettingsFixture();
          await mountAccountSettings(tester, repo, assistant: assistant);
          await openAccountForm(tester, assistant);
          final save = tester
              .widget<FilledButton>(
                find.ancestor(
                  of: find.text('Сохранить'),
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed!;
          switch (change) {
            case 'account':
              repo.token = 'different-synthetic-parent';
              repo.snapshot!['user'] = {'id': 'other-parent', 'role': 'parent'};
            case 'server':
              repo.endpoint = 'https://different.invalid';
            case 'generation':
              repo.generation++;
            case 'role':
            case 'restored role':
              repo.snapshot!['user']['role'] = 'child';
          }
          repo.notifyListeners();
          if (change == 'restored role') {
            repo.snapshot!['user']['role'] = 'parent';
            repo.notifyListeners();
          }
          save();
          await tester.pumpAndSettle();
          expect(repo.changes, isEmpty);
          expect(find.byType(TextFormField), findsNothing);
          expect(find.text('Сохранить'), findsNothing);
          expect(
            find.textContaining('Семейный доступ изменился'),
            findsWidgets,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$section masks a draft when its repository instance is replaced',
      (tester) async {
        final repo = AccountSettingsFixture(), next = AccountSettingsFixture();
        final selected = ValueNotifier(repo);
        addTearDown(() {
          selected.dispose();
          next.client.close();
          next.dispose();
        });
        await mountAccountSettings(
          tester,
          repo,
          assistant: assistant,
          selection: selected,
        );
        await openAccountForm(tester, assistant);
        selected.value = next;
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('Сохранить'), findsNothing);
        expect(repo.changes, isEmpty);
        expect(next.changes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$section keeps a same-owner offline draft and saves once after reconnect',
      (tester) async {
        final repo = AccountSettingsFixture();
        await mountAccountSettings(tester, repo, assistant: assistant);
        await openAccountForm(tester, assistant);
        repo.online = false;
        repo.notifyListeners();
        await tester.pumpAndSettle();
        final save = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Сохранить'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(save.onPressed, isNull);
        expect(repo.changes, isEmpty);
        expect(find.byType(Form), findsOneWidget);
        repo.online = true;
        repo.notifyListeners();
        await tester.pumpAndSettle();
        await saveAccountForm(tester);
        expect(repo.changes, hasLength(1));
        expect(
          repo.changes.single['path'],
          assistant ? '/v1/assistant/private-rule' : '/v1/family',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$section opens only one form for two rapid callbacks', (
      tester,
    ) async {
      final repo = AccountSettingsFixture();
      await mountAccountSettings(tester, repo, assistant: assistant);
      final finder = find.text(
        assistant ? 'Добавить правило' : 'Часовой пояс и тихие часы',
      );
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final VoidCallback callback = assistant
          ? tester
                .widget<FilledButton>(
                  find.ancestor(
                    of: finder,
                    matching: find.byType(FilledButton),
                  ),
                )
                .onPressed!
          : tester
                .widget<OutlinedButton>(
                  find.ancestor(
                    of: finder,
                    matching: find.byType(OutlinedButton),
                  ),
                )
                .onPressed!;
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(FamilyForm, skipOffstage: false), findsOneWidget);
      expect(repo.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final assistant in [false, true]) {
    testWidgets(
      '${assistant ? 'assistant' : 'quiet hours'} handles an old failed save after access changed',
      (tester) async {
        final repo = AccountSettingsFixture()
          ..reply = Completer<Map<String, dynamic>>();
        await mountAccountSettings(tester, repo, assistant: assistant);
        await openAccountForm(tester, assistant);
        final save = find.text('Сохранить');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pump();
        repo.generation++;
        repo.token = 'replacement-parent';
        repo.notifyListeners();
        repo.reply!.completeError(ApiFailure(422, 'Ошибка старой семьи'));
        await tester.pumpAndSettle();
        expect(repo.changes, hasLength(1));
        expect(find.byType(Form), findsNothing);
        expect(find.text('Ошибка старой семьи'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${assistant ? 'assistant' : 'quiet hours'} masks an open form if its parent route is removed',
      (tester) async {
        final repo = AccountSettingsFixture();
        await mountAccountSettings(tester, repo, assistant: assistant);
        final parent = ModalRoute.of(
          tester.element(
            find.byType(assistant ? AssistantSettings : SettingsScreen),
          ),
        )!;
        await openAccountForm(tester, assistant);
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .removeRoute(parent);
        await tester.pumpAndSettle();
        expect(find.byType(Form), findsNothing);
        expect(find.text('Сохранить'), findsNothing);
        expect(repo.changes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final queuedFailure in [false, true]) {
    testWidgets(
      'assistant uncertain delete stays single and resolves a failed retry ($queuedFailure)',
      (tester) async {
        final repo = AccountSettingsFixture()
          ..reply = Completer<Map<String, dynamic>>();
        await mountAccountSettings(tester, repo, assistant: true);
        final delete = tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_outline),
            )
            .onPressed!;
        delete();
        delete();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        final confirm = tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text('Удалить'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed!;
        confirm();
        confirm();
        await tester.pumpAndSettle();
        expect(repo.changes, hasLength(1));
        delete();
        await tester.pump();
        expect(repo.changes, hasLength(1));
        repo.commands.add({
          'path': '/v1/assistant/private-rule',
          'state': 'pending',
        });
        if (queuedFailure) {
          repo.reply!.completeError(
            QueuedCommandFailure(
              503,
              'Проверочный обрыв',
              commandId: 'synthetic-command',
            ),
          );
        } else {
          repo.reply!.complete({'queued': true});
        }
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.delete_outline),
              )
              .onPressed,
          isNull,
        );
        expect(find.textContaining('Удаление ожидает сверки'), findsOneWidget);
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.delete_outline),
              )
              .onPressed,
          isNull,
        );
        repo.commands.single['state'] = 'failed';
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.delete_outline),
              )
              .onPressed,
          isNotNull,
        );
        expect(repo.changes, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'assistant refresh errors have an explanation without exposing a replaced account',
    (tester) async {
      final repo = AccountSettingsFixture()..failRefresh = true;
      await mountAccountSettings(tester, repo, assistant: true, scale: 1.5);
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('Проверочная ошибка связи'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'assistant list stops showing private rules after account change',
    (tester) async {
      final repo = AccountSettingsFixture();
      await mountAccountSettings(tester, repo, assistant: true);
      repo.generation++;
      repo.token = 'different-parent';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Личное правило первой семьи'), findsNothing);
      expect(find.textContaining('Личные приготовления'), findsNothing);
      expect(find.text('Добавить правило'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'assistant delete confirmation cannot act after another parent signs in',
    (tester) async {
      final repo = AccountSettingsFixture();
      await mountAccountSettings(tester, repo, assistant: true);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
      await tester.pumpAndSettle();
      final oldDelete = tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Удалить'),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed!;
      repo.token = 'different-parent';
      repo.generation++;
      repo.notifyListeners();
      oldDelete();
      await tester.pumpAndSettle();
      expect(repo.changes, isEmpty);
      expect(find.text('Личное правило первой семьи'), findsNothing);
      expect(find.text('Удалить'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
