import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/activity_lists.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/settings_screen.dart';
import 'package:mykids_family/visuals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:workmanager/workmanager.dart';

class ActivityWire extends http.BaseClient {
  final inner = http.Client();
  bool offline = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw const SocketException('Synthetic connection loss');
    request.persistentConnection = false;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('owned Android filters and family money workflows', (
    tester,
  ) async {
    final emulator = await Process.run('/system/bin/getprop', [
      'ro.kernel.qemu',
    ]);
    expect(
      Platform.isAndroid && emulator.stdout.toString().trim() == '1',
      true,
    );
    HttpOverrides.global = null;
    tzdata.initializeTimeZones();
    const endpoint = 'http://127.0.0.1:18807';
    final support = await getApplicationSupportDirectory();
    final wire = ActivityWire();
    final repo = FamilyRepository(client: wire);
    final background = BackgroundServices(repo);
    final control = http.Client();
    final errors = <ApiFailure>[];
    var actionsInFlight = 0;
    double? scaleOverride;

    Future<void> until(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Expected native state absent');
        }
        await tester.pump(const Duration(milliseconds: 150));
      }
      await tester.pumpAndSettle();
    }

    Future<void> idle() => until(() => actionsInFlight == 0 && !repo.syncing);

    Future<void> stage(String name) async {
      await idle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await File('${support.path}/mykids-quality118-stage.json')
          .writeAsString(jsonEncode({'stage': name}));
      final ack = File('${support.path}/mykids-quality118-continue-$name');
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!await ack.exists()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Capture timed out at $name');
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await ack.delete();
    }

    Future<void> reveal(Finder target) async {
      await tester.pumpAndSettle();
      if (target.evaluate().isEmpty ||
          target.hitTestable().evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          target,
          230,
          maxScrolls: 100,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder target) async {
      await reveal(target);
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target.hitTestable());
      await tester.pumpAndSettle();
    }

    Future<void> perform(Future<Map<String, dynamic>> Function() action) async {
      actionsInFlight++;
      try {
        await action();
      } on ApiFailure catch (error) {
        if (error.status != 409) rethrow;
        errors.add(error);
      } finally {
        actionsInFlight--;
      }
    }

    Future<void> mount(Widget Function() body, String title) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: familyTheme(false),
          builder: (context, child) => scaleOverride == null
              ? child!
              : MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scaleOverride)),
                  child: child!,
                ),
          home: Scaffold(
            appBar: AppBar(title: Text(title)),
            body: ListenableBuilder(
              listenable: repo,
              builder: (_, _) => repo.signedIn && repo.snapshot != null
                  ? body()
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> login(String name) async {
      await idle();
      if (repo.signedIn) await repo.logout(remote: false);
      await repo.login(
        endpoint,
        'quality118-$name',
        'synthetic-native-money-118',
      );
      await tester.pumpAndSettle();
    }

    Future<Map<String, dynamic>> stats() async {
      final response = await control.get(
        Uri.parse('$endpoint/quality118/stats'),
        headers: {'X-MyKIDS-QA': 'quality118-loopback-only'},
      );
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    Future<void> historyVisibility(bool visible) async {
      final response = await control.post(
        Uri.parse('$endpoint/quality118/history-visibility'),
        headers: {
          'X-MyKIDS-QA': 'quality118-loopback-only',
          'content-type': 'application/json',
        },
        body: jsonEncode({'visible': visible}),
      );
      expect(response.statusCode, 200);
      await repo.sync();
      await tester.pumpAndSettle();
    }

    Finder filter(String label) => find.byWidgetPredicate(
      (widget) => widget is ActivityFilter && widget.label == label,
    );
    String selected(String label) =>
        tester.widget<ActivityFilter>(filter(label)).value;
    Future<void> openFilter(String label) async {
      await reveal(filter(label));
      await tester.tap(
        find.descendant(
          of: filter(label),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choose(String label, String choice) async {
      await openFilter(label);
      final option = find.text(choice).last;
      if (option.hitTestable().evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          option,
          160,
          maxScrolls: 100,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await tester.tap(option.hitTestable());
      await tester.pumpAndSettle();
    }

    Future<void> tasks() => mount(
      () => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FamilySection(
            title: 'Задания и результаты',
            icon: 2,
            children: [TodayTaskList(repository: repo, onOpen: () {})],
          ),
        ],
      ),
      'Задания',
    );
    Future<void> history() async {
      await mount(
        () => SettingsScreen(
          repository: repo,
          background: background,
          perform: perform,
          onUpdates: () async {},
        ),
        'Настройки семьи',
      );
      await reveal(filter('Период истории'));
    }

    Future<void> money() => mount(
      () => MoneyScreen(repository: repo, perform: perform),
      'Семейные монеты',
    );

    Map<String, dynamic> reward(String title) =>
        repo.rows('rewards').singleWhere((row) => row['title'] == title);
    Future<Finder> openReward(String title) async {
      final row = reward(title);
      final tile = find.byKey(ValueKey('reward-${row['id']}'));
      final heading = find.text('$title · ${row['price']} монет');
      await reveal(heading);
      if (find
          .descendant(of: tile, matching: find.text('Копить на это'))
          .evaluate()
          .isEmpty) {
        await tap(heading);
      }
      return tile;
    }

    Future<void> rewardAction(String title, String label) async {
      final tile = await openReward(title);
      await tap(find.descendant(of: tile, matching: find.text(label)));
      await idle();
    }

    Future<void> requestAction(String label) async {
      final row = repo.rows('redemptions').last;
      final tile = find.byKey(ValueKey('redemption-${row['id']}'));
      await tap(
        find.descendant(
          of: tile,
          matching: find.text('${row['title']} · ${row['amount']}'),
        ),
      );
      await tap(find.descendant(of: tile, matching: find.text(label)));
      await idle();
    }

    try {
      await Workmanager().initialize(backgroundSync);
      await repo.initialize();
      await login('child');
      await tasks();
      expect(selected('Период заданий'), 'today');
      await stage('tasks-default');
      await choose('Состояние задания', 'Не выполнено');
      expect(find.text('Найдено: 0'), findsOneWidget);
      await stage('tasks-empty');
      await tap(find.text('Сбросить фильтры'));
      expect(selected('Состояние задания'), 'all');
      expect(find.text('Найдено: 11'), findsOneWidget);
      await stage('tasks-reset');
      for (final design in GameDesign.all) {
        gameDesign.value = design;
        await tasks();
        final label = find.text('Сегодня и просроченные');
        await reveal(label);
        final paragraph = tester.renderObject<RenderParagraph>(label);
        final natural = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
        )..layout(maxWidth: paragraph.size.width);
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(natural.height - .1),
        );
        natural.dispose();
        expect(
          MediaQuery.textScalerOf(tester.element(filter('Период заданий')))
              .scale(14),
          greaterThanOrEqualTo(20),
        );
        await stage('tasks-style-${design.id}');
      }
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
      ]);
      await until(
        () => tester.view.physicalSize.width > tester.view.physicalSize.height,
      );
      scaleOverride = 2;
      await tasks();
      await stage('tasks-large-landscape');
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await until(
        () => tester.view.physicalSize.height > tester.view.physicalSize.width,
      );
      scaleOverride = null;

      await login('parent');
      await history();
      await stage('history-default');
      final relative = repo
          .rows('members')
          .singleWhere((row) => row['role'] == 'relative');
      final relativeName = relative['name'] as String;
      await openFilter('Участник');
      expect(find.text(relativeName).last.hitTestable(), findsOneWidget);
      await stage('history-live-menu');
      await historyVisibility(false);
      expect(find.text(relativeName), findsNothing);
      expect(selected('Участник'), 'all');
      await reveal(filter('Период истории'));
      await stage('history-options-refreshed');
      await historyVisibility(true);
      await choose('Участник', relativeName);
      expect(selected('Участник'), relative['id']);
      await stage('history-selected-member');
      await historyVisibility(false);
      expect(selected('Участник'), 'all');
      await stage('history-actor-cleared');
      await historyVisibility(true);
      expect(selected('Участник'), 'all');
      await stage('history-actor-stays-cleared');
      await choose('Вид действия', 'Звонки');
      expect(find.text('Найдено: 0'), findsOneWidget);
      await reveal(find.text('Сбросить фильтры'));
      await stage('history-empty');
      await tap(find.text('Сбросить фильтры'));
      expect(selected('Вид действия'), 'all');
      await stage('history-reset');
      await openFilter('Участник');
      await repo.sync();
      await tester.pumpAndSettle();
      expect(find.text(relativeName).last.hitTestable(), findsOneWidget);
      await stage('history-unchanged-menu');
      await tester.tap(find.text(relativeName).last);
      await tester.pumpAndSettle();
      await choose('Период истории', 'Вся доступная история');
      await login('outside-parent');
      await reveal(filter('Период истории'));
      expect(selected('Период истории'), 'week');
      expect(selected('Вид действия'), 'all');
      expect(selected('Участник'), 'all');
      expect(find.text(relativeName), findsNothing);
      await stage('history-new-owner');
      expect((await stats())['writes'], isEmpty);

      await login('child');
      await money();
      await rewardAction('Робот-исследователь', 'Копить на это');
      expect(
        repo.snapshot!['goal']['reward_id'],
        reward('Робот-исследователь')['id'],
      );
      await stage('money-goal');
      await money();
      await rewardAction('Робот-исследователь', 'Попросить награду');
      expect(repo.snapshot!['balance']['reserved'], 60);
      expect(repo.snapshot!['balance']['available'], 90);
      await stage('money-request');
      await money();
      await requestAction('Отменить заявку');
      expect(repo.snapshot!['balance']['reserved'], 0);
      expect(repo.snapshot!['balance']['available'], 150);
      await stage('money-cancelled');
      await money();
      wire.offline = true;
      repo.online = false;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      await tap(find.text('Обменять монеты на рубли'));
      expect(find.byType(FamilyForm), findsOneWidget);
      await reveal(find.text('Сохранить'));
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Сохранить'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Нет связи с сервером'), findsOneWidget);
      await stage('money-offline-form');
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      wire.offline = false;
      await repo.sync();
      await idle();
      expect(repo.online, true);
      await stage('money-reconnected');
      await money();
      await rewardAction('Космический корабль', 'Копить на это');
      expect(
        repo.snapshot!['goal']['reward_id'],
        reward('Космический корабль')['id'],
      );
      await money();
      final tile = await openReward('Робот-исследователь');
      final staleGoal = tester
          .widget<TextButton>(
            find.ancestor(
              of: find.descendant(
                of: tile,
                matching: find.text('Копить на это'),
              ),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed!;
      await tap(
        find.descendant(of: tile, matching: find.text('Попросить награду')),
      );
      await idle();
      await login('parent');
      final beforeStale = ((await stats())['writes'] as List).length;
      staleGoal();
      await tester.pumpAndSettle();
      expect(((await stats())['writes'] as List).length, beforeStale);
      await stage('money-old-owner-blocked');
      await money();
      await requestAction('Взять для выдачи');
      expect(repo.rows('redemptions').last['status'], 'claimed');
      await stage('money-parent-claimed');
      await money();
      await requestAction('Уже выдал — подтвердить');
      expect(find.byType(AlertDialog), findsOneWidget);
      await stage('money-consent-current');
      final approve = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить'),
          )
          .onPressed!;
      final cancel = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Отмена'))
          .onPressed!;
      final navigator = Navigator.of(tester.element(find.byType(AlertDialog)));
      final covering = navigator.push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Проверка другого экрана')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      approve();
      cancel();
      await tester.pumpAndSettle();
      expect(find.text('Проверка другого экрана'), findsOneWidget);
      expect(((await stats())['writes'] as List).length, 6);
      await stage('money-consent-cover-preserved');
      navigator.pop(false);
      await covering;
      await tester.pumpAndSettle();
      await tap(find.widgetWithText(TextButton, 'Отмена'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.rows('redemptions').last['status'], 'claimed');
      expect(((await stats())['writes'] as List).length, 6);
      await stage('money-consent-cancelled');
      await money();
      await requestAction('Ещё не выдал — вернуть в ожидание');
      expect(repo.rows('redemptions').last['status'], 'pending');
      await stage('money-parent-released');
      await money();
      await requestAction('Взять для выдачи');
      await money();
      await requestAction('Отклонить до выдачи');
      expect(repo.rows('redemptions').last['status'], 'rejected');
      expect(repo.snapshot!['balance']['total'], 150);
      expect(repo.snapshot!['balance']['available'], 150);
      expect(repo.snapshot!['balance']['reserved'], 0);
      await stage('money-parent-rejected');
      final finalStats = await stats();
      expect((finalStats['writes'] as List).length, 9);
      expect(finalStats['ledger'], [
        {'actual': 150, 'source_type': 'task'},
      ]);
      expect(finalStats['goal_title'], 'Космический корабль');
      expect(finalStats['real_families'], false);
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
      await File('${support.path}/mykids-quality118-server-stats.json')
          .writeAsString(jsonEncode(finalStats));
      await File('${support.path}/mykids-quality118-proof.json').writeAsString(
        jsonEncode({
          'passed': true,
          'physical_phone': false,
          'task_filters_reset': true,
          'large_text_and_five_styles': true,
          'live_choices_refresh': true,
          'unchanged_refresh_keeps_menu': true,
          'actor_selection_stays_cleared': true,
          'owner_change_resets_filters': true,
          'goal_switching_working': true,
          'reward_request_cancel_working': true,
          'reward_claim_release_reject_working': true,
          'offline_form_blocks_save': true,
          'stale_money_callback_blocked': true,
          'money_consent_preserves_covering_route': true,
          'money_consent_cancel_sends_no_action': true,
          'no_extra_ledger_entries': true,
        }),
      );
    } finally {
      wire.offline = false;
      await idle();
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      background.dispose();
      control.close();
      repo.client.close();
      repo.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
