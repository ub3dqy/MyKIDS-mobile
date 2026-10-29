import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/design_today.dart';
import 'package:mykids_family/engagement/discovery_page.dart';
import 'package:mykids_family/engagement/robot_route_game.dart';
import 'package:mykids_family/engagement/space_memory_game.dart';
import 'package:mykids_family/engagement/robot_workshop_game.dart';
import 'package:mykids_family/engagement/engagement_scope.dart';
import 'package:mykids_family/engagement/production_controller.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:workmanager/workmanager.dart';

class OfflineWire extends http.BaseClient {
  final inner = http.Client();
  bool offline = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw const SocketException('Synthetic expedition offline');
    // The loopback connection crosses the private ADB reverse transport.
    // Keep each probe connection independent across long screenshot pauses.
    request.persistentConnection = false;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'space expedition uses real confirmed progress and never game-earned coins',
    (tester) async {
      final emulator = await Process.run('/system/bin/getprop', [
        'ro.kernel.qemu',
      ]);
      expect(
        Platform.isAndroid && emulator.stdout.toString().trim() == '1',
        true,
      );
      expect(gameDesign.value?.id, 'squad');
      HttpOverrides.global = null;
      tzdata.initializeTimeZones();
      const endpoint = 'http://127.0.0.1:18805';
      final support = await getApplicationSupportDirectory();
      final wire = OfflineWire();
      final repo = FamilyRepository(client: wire);
      final controller = ProductionEngagementController(repo);
      final control = http.Client();
      final page = ValueNotifier(0);
      String? parentToken;
      var toggleIndex = 0;
      Future<void> stage(String name) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        await File('${support.path}/mykids-quality116-stage.json')
            .writeAsString(jsonEncode({'stage': name}));
        final ack = File('${support.path}/mykids-quality116-continue-$name');
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (!await ack.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Coordinator timed out: $name');
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await ack.delete();
      }

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

      Future<void> tap(Finder finder, {double scrollStep = 230}) async {
        if (finder.evaluate().isEmpty &&
            find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            finder,
            scrollStep,
            maxScrolls: 80,
            scrollable: find.byType(Scrollable).last,
          );
        }
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        expect(finder.hitTestable(), findsOneWidget);
        await tester.tap(finder.hitTestable());
        await tester.pumpAndSettle();
      }

      Future<Map<String, dynamic>> stats() async {
        final response = await http.get(
          Uri.parse('$endpoint/quality116/stats'),
          headers: {'X-MyKIDS-QA': 'quality116-loopback-only'},
        );
        expect(response.statusCode, 200);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      Future<Map<String, dynamic>> parentRequest(
        String path, {
        Map<String, dynamic>? data,
        String? key,
      }) async {
        final headers = {
          'Authorization': 'Bearer $parentToken',
          'Content-Type': 'application/json',
        };
        if (key != null) {
          headers['Idempotency-Key'] = key;
        }
        final result = data == null
            ? await http.get(Uri.parse('$endpoint$path'), headers: headers)
            : await http.post(
                Uri.parse('$endpoint$path'),
                headers: headers,
                body: jsonEncode(data),
              );
        expect(result.statusCode, 200, reason: result.body);
        return jsonDecode(result.body) as Map<String, dynamic>;
      }

      Future<void> setEnabled(bool enabled) async {
        final snapshot = await parentRequest('/v1/snapshot');
        final entry = (snapshot['engagement'] as List).single as Map;
        await parentRequest(
          '/v1/engagement/${entry['child_id']}/commands',
          data: {
            'action': 'set_enabled',
            'feature': 'adventure',
            'value': enabled,
            'expected_revision': entry['revision'],
          },
          key: 'quality116-toggle-${toggleIndex++}',
        );
        await repo.refreshAfterChange();
        await tester.pumpAndSettle();
      }

      Future<void> openMap() async {
        page.value = 0;
        await tester.pumpAndSettle();
        await tap(find.text('Космос'));
        await until(() => find.byType(DiscoveryPage).evaluate().isNotEmpty);
      }

      Future<void> closePage() async {
        await tester.tap(find.byType(BackButton).last);
        await tester.pumpAndSettle();
      }

      Future<void> firstStop() async {
        await tap(find.byKey(const ValueKey('discovery-launch')));
        await until(() => find.byType(DiscoveryStopPage).evaluate().isNotEmpty);
      }

      Future<void> robotTraining() async {
        await tap(find.byKey(const ValueKey('robot-training-entry')));
        await until(() => find.byType(RobotTrainingPage).evaluate().isNotEmpty);
      }

      Future<void> robotBoard() async {
        final board = find.byKey(const ValueKey('robot-board'));
        await tester.scrollUntilVisible(
          board,
          220,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(board);
        await tester.pumpAndSettle();
      }

      List<String> cardLabels() => [
        for (var i = 0; i < 6; i++)
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byKey(ValueKey('memory-card-$i')),
                  matching: find.byType(Text),
                ),
              )
              .data!,
      ];

      try {
        await Workmanager().initialize(backgroundSync);
        await repo.initialize();
        await repo.login(
          endpoint,
          'quality116-child',
          'synthetic-native-expedition-123',
        );
        final parentLogin = await control.post(
          Uri.parse('$endpoint/v1/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': 'quality116-parent',
            'password': 'synthetic-native-expedition-123',
          }),
        );
        expect(parentLogin.statusCode, 200);
        parentToken = (jsonDecode(parentLogin.body) as Map)['token'] as String;
        await tester.pumpWidget(
          ValueListenableBuilder<GameDesign?>(
            valueListenable: gameDesign,
            builder: (_, _, _) => EngagementScope(
              controller: controller,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: const Locale('ru'),
                supportedLocales: const [Locale('ru')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: familyTheme(true),
                home: Scaffold(
                  appBar: AppBar(title: const Text('MyKIDS')),
                  body: ListenableBuilder(
                    listenable: repo,
                    builder: (_, _) => !repo.signedIn || repo.snapshot == null
                        ? const SizedBox.shrink()
                        : ValueListenableBuilder<int>(
                            valueListenable: page,
                            builder: (_, selected, _) => selected == 2
                                ? TaskScreen(
                                    repository: repo,
                                    perform: (action) async {
                                      await action();
                                    },
                                  )
                                : GameToday(
                                    repository: repo,
                                    openPage: (next) => page.value = next,
                                  ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheFamilyArtwork(tester.element(find.byType(GameToday))),
        );
        await tester.pumpAndSettle();
        expect(controller.completedCount, 0);
        await stage('home-entry');
        await openMap();
        expect(find.text('Открыто находок: 1 из 30'), findsOneWidget);
        await stage('map-squad');
        for (final style in ['blocks', 'comic', 'workshop', 'islands']) {
          gameDesign.value = GameDesign.byId(style);
          await tester.pumpAndSettle();
          await stage('map-$style');
        }
        gameDesign.value = GameDesign.byId('squad');
        await tester.pumpAndSettle();
        final beforePlay = await stats();
        await firstStop();
        await stage('riddle');
        await tap(find.byKey(const ValueKey('discovery-answer-1')));
        await until(
          () => find.textContaining('Подсказка:').evaluate().isNotEmpty,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('discovery-feedback')),
        );
        await stage('hint');
        await tap(find.byKey(const ValueKey('discovery-answer-0')));
        await until(() => find.textContaining('Верно!').evaluate().isNotEmpty);
        await tester.ensureVisible(
          find.byKey(const ValueKey('discovery-feedback')),
        );
        await stage('solved');
        final afterPlay = await stats();
        expect(
          (afterPlay['requests'] as List).length,
          (beforePlay['requests'] as List).length,
        );
        expect(afterPlay['writes'], isEmpty);
        expect(repo.snapshot!['balance']['total'], 0);
        await closePage();

        final beforeRobot = await stats();
        wire.offline = true;
        repo.online = false;
        repo.notifyListeners();
        await robotTraining();
        await robotBoard();
        await stage('robot-start');
        for (final style in ['blocks', 'comic', 'workshop', 'islands']) {
          gameDesign.value = GameDesign.byId(style);
          await tester.pumpAndSettle();
          await robotBoard();
          await stage('robot-$style');
        }
        gameDesign.value = GameDesign.byId('squad');
        await tester.pumpAndSettle();
        await tap(find.byKey(const ValueKey('robot-left')));
        expect(find.textContaining('край площадки'), findsOneWidget);
        await stage('robot-edge');
        await tap(find.byKey(const ValueKey('robot-right')));
        await tap(find.byKey(const ValueKey('robot-up')));
        expect(find.textContaining('клетка закрыта'), findsOneWidget);
        await stage('robot-obstacle');
        await tap(find.byKey(const ValueKey('robot-restart')));
        await tap(find.text('Подсказка'));
        expect(find.byKey(const ValueKey('robot-hint')), findsOneWidget);
        await stage('robot-hint');
        const routes = [
          [
            RobotDirection.up,
            RobotDirection.up,
            RobotDirection.up,
            RobotDirection.right,
            RobotDirection.right,
            RobotDirection.right,
          ],
          [
            RobotDirection.down,
            RobotDirection.down,
            RobotDirection.down,
            RobotDirection.right,
            RobotDirection.right,
            RobotDirection.right,
          ],
          [
            RobotDirection.left,
            RobotDirection.up,
            RobotDirection.up,
            RobotDirection.up,
            RobotDirection.left,
            RobotDirection.left,
          ],
        ];
        for (var challenge = 0; challenge < routes.length; challenge++) {
          if (challenge > 0) {
            await tap(
              find.byKey(ValueKey('robot-challenge-$challenge')),
              scrollStep: -230,
            );
          }
          for (final direction in routes[challenge]) {
            await tap(find.byKey(ValueKey('robot-${direction.name}')));
          }
          expect(
            find.text(robotRouteChallenges[challenge].arrival),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('robot-feedback')),
          );
          await stage(
            ['robot-beacon', 'robot-courier', 'robot-garden'][challenge],
          );
        }
        await tap(find.byKey(const ValueKey('robot-restart')));
        expect(find.textContaining('Лучик: ряд 4, клетка 4.'), findsOneWidget);
        await robotBoard();
        await stage('robot-restarted');
        await closePage();
        await tap(find.byKey(const ValueKey('space-station-entry')));
        expect(find.byType(SpaceMemoryGame), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('memory-board')));
        await stage('pairs-start');
        for (final style in ['blocks', 'comic', 'workshop', 'islands']) {
          gameDesign.value = GameDesign.byId(style);
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('memory-board')),
          );
          await stage('pairs-$style');
        }
        gameDesign.value = GameDesign.byId('squad');
        await tester.pumpAndSettle();
        await tap(find.byKey(const ValueKey('memory-peek')));
        await tester.ensureVisible(find.byKey(const ValueKey('memory-board')));
        await stage('pairs-peek');
        final initialCards = cardLabels();
        final other = initialCards.indexWhere((c) => c != initialCards.first);
        await tap(find.byKey(const ValueKey('memory-peek')));
        await tap(find.byKey(const ValueKey('memory-card-0')));
        await tap(find.byKey(ValueKey('memory-card-$other')));
        expect(find.textContaining('Карточки разные.'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('memory-feedback')),
        );
        await stage('pairs-mismatch');
        await tap(find.byKey(const ValueKey('memory-next')));
        for (var level = 0; level < spaceMemoryChallenges.length; level++) {
          if (level > 0) {
            await tap(
              find.byKey(ValueKey('station-level-$level')),
              scrollStep: -230,
            );
          }
          await tap(find.byKey(const ValueKey('memory-peek')));
          final cards = cardLabels();
          await tap(find.byKey(const ValueKey('memory-peek')));
          for (final symbol in cards.toSet()) {
            for (var i = 0; i < cards.length; i++) {
              if (cards[i] == symbol) {
                await tap(find.byKey(ValueKey('memory-card-$i')));
              }
            }
          }
          expect(find.text('Найдено пар: 3 из 3'), findsOneWidget);
          await tester.ensureVisible(
            find.byKey(const ValueKey('memory-feedback')),
          );
          await stage('pairs-complete-$level');
        }
        await tap(find.byKey(const ValueKey('memory-restart')));
        expect(find.text('Найдено пар: 0 из 3'), findsOneWidget);
        await tap(
          find.byKey(const ValueKey('station-game-workshop')),
          scrollStep: -230,
        );
        expect(find.byType(RobotWorkshopGame), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('workshop-robot')),
        );
        await stage('workshop-start');
        await tap(find.byKey(const ValueKey('workshop-part-fins')));
        expect(find.text('Детали робота: 0 из 3'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('workshop-hint')));
        await stage('workshop-wrong');
        await tap(find.byKey(const ValueKey('workshop-restart')));
        await tap(find.byKey(const ValueKey('workshop-show-hint')));
        await tester.ensureVisible(find.byKey(const ValueKey('workshop-hint')));
        await stage('workshop-hint');
        for (var level = 0; level < robotWorkshopChallenges.length; level++) {
          if (level > 0) {
            await tap(
              find.byKey(ValueKey('station-level-$level')),
              scrollStep: -230,
            );
          }
          for (final step in robotWorkshopChallenges[level].steps) {
            await tap(
              find.byKey(ValueKey('workshop-part-${step.answer.name}')),
            );
          }
          expect(find.text('Детали робота: 3 из 3'), findsOneWidget);
          await tester.ensureVisible(
            find.byKey(const ValueKey('workshop-feedback')),
          );
          await stage('workshop-complete-$level');
        }
        await tap(find.byKey(const ValueKey('workshop-restart')));
        expect(find.text('Детали робота: 0 из 3'), findsOneWidget);
        wire.offline = false;
        repo.online = true;
        repo.notifyListeners();
        final afterRobot = await stats();
        expect(
          (afterRobot['requests'] as List).length,
          (beforeRobot['requests'] as List).length,
        );
        expect(afterRobot['writes'], isEmpty);
        expect(controller.completedCount, 0);
        expect(repo.snapshot!['balance']['total'], 0);
        await closePage();
        await tap(find.byKey(const ValueKey('discovery-beacon')));
        expect(find.text('Загадка Лучика'), findsNothing);
        await stage('locked');
        await tap(find.text('Выбрать дело'));
        await until(
          () =>
              find.byType(TaskScreen).evaluate().isNotEmpty &&
              find.byType(DiscoveryPage).evaluate().isEmpty,
        );
        await stage('tasks-return');
        final taskId = repo.rows('tasks').single['id'] as String;
        await repo.mutate('/v1/tasks/$taskId/submissions', {
          'task_version': 1,
          'note': 'Рюкзак подготовлен',
          'marked_at': DateTime.now().toUtc().toIso8601String(),
        });
        await openMap();
        expect(controller.completedCount, 0);
        expect(find.text('Открыто находок: 1 из 30'), findsOneWidget);
        await stage('submitted-map');
        for (var repeat = 0; repeat < 2; repeat++) {
          await parentRequest(
            '/v1/tasks/$taskId/actions',
            data: {'action': 'approve', 'task_version': 1},
            key: 'quality116-parent-approve',
          );
        }
        await repo.refreshAfterChange();
        await until(() => controller.completedCount == 1);
        expect(find.text('Открыто находок: 2 из 30'), findsOneWidget);
        expect(repo.snapshot!['balance']['total'], 7);
        await stage('confirmed-map');
        await tap(find.byKey(const ValueKey('discovery-beacon')));
        expect(find.text('Твоя находка: Карманный маячок'), findsOneWidget);
        await stage('new-find');
        await closePage();
        await closePage();
        final beforeOffline = await stats();
        wire.offline = true;
        repo.online = false;
        repo.notifyListeners();
        await openMap();
        expect(find.text('Открыто находок: 2 из 30'), findsOneWidget);
        await stage('offline-map');
        final afterOffline = await stats();
        expect(
          (afterOffline['requests'] as List).length,
          (beforeOffline['requests'] as List).length,
        );
        wire.offline = false;
        repo.online = true;
        repo.notifyListeners();
        await setEnabled(false);
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        expect(find.byKey(const ValueKey('discovery-progress')), findsNothing);
        await stage('disabled-map');
        await setEnabled(true);
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        await closePage();
        await openMap();
        expect(find.text('Открыто находок: 2 из 30'), findsOneWidget);
        await robotTraining();
        await setEnabled(false);
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        expect(find.byType(RobotRouteGame), findsNothing);
        await stage('robot-disabled');
        await setEnabled(true);
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        await closePage();
        await closePage();
        await openMap();
        await tap(find.byKey(const ValueKey('space-station-entry')));
        await setEnabled(false);
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        expect(find.byType(SpaceMemoryGame), findsNothing);
        await stage('station-disabled');
        await setEnabled(true);
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        await closePage();
        await closePage();
        await openMap();
        await tap(find.byKey(const ValueKey('space-station-entry')));
        final staleCard = tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('memory-card-0')))
            .onPressed!;
        final stationBack = tester
            .widget<BackButton>(find.byType(BackButton).last)
            .onPressed!;
        final stationNav = Navigator.of(
          tester.element(find.byType(SpaceStationPage)),
        );
        stationNav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Важный экран станции')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        staleCard();
        stationBack();
        await tester.pumpAndSettle();
        expect(find.text('Важный экран станции'), findsOneWidget);
        await stage('covered-station');
        stationNav.pop();
        await tester.pumpAndSettle();
        await repo.logout(remote: false);
        await repo.login(
          endpoint,
          'quality116-outside-child',
          'synthetic-native-expedition-123',
        );
        staleCard();
        await tester.pumpAndSettle();
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        expect(find.byType(SpaceMemoryGame), findsNothing);
        await stage('station-session-hidden');
        await closePage();
        await closePage();
        await repo.logout(remote: false);
        await repo.login(
          endpoint,
          'quality116-child',
          'synthetic-native-expedition-123',
        );
        await openMap();
        await firstStop();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('discovery-answer-0')),
          220,
          scrollable: find.byType(Scrollable).last,
        );
        final answer = tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('discovery-answer-0')),
            )
            .onPressed!;
        final back = tester
            .widget<BackButton>(find.byType(BackButton).last)
            .onPressed!;
        final nav = Navigator.of(
          tester.element(find.byType(DiscoveryStopPage)),
        );
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('Важный экран'))),
          ),
        );
        await tester.pumpAndSettle();
        answer();
        back();
        await tester.pumpAndSettle();
        expect(find.text('Важный экран'), findsOneWidget);
        await stage('covered-story');
        nav.pop();
        await tester.pumpAndSettle();
        await repo.logout(remote: false);
        await repo.login(
          endpoint,
          'quality116-outside-child',
          'synthetic-native-expedition-123',
        );
        answer();
        await tester.pumpAndSettle();
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        expect(find.text('Загадка Лучика'), findsNothing);
        await stage('session-hidden');
        await closePage();
        await closePage();
        await repo.logout(remote: false);
        await repo.login(
          endpoint,
          'quality116-explorer',
          'synthetic-native-expedition-123',
        );
        await openMap();
        expect(controller.completedCount, 160);
        expect(find.text('Открыто находок: 30 из 30'), findsOneWidget);
        expect(repo.snapshot!['balance']['total'], 0);
        await tap(find.byKey(const ValueKey('discovery-continue')));
        expect(
          find.text('Твоя находка: Эмблема добрых роботов'),
          findsOneWidget,
        );
        await tap(find.byKey(const ValueKey('discovery-answer-0')));
        expect(find.textContaining('Верно!'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('discovery-feedback')),
        );
        await stage('new-world-story');
        final finalStats = await stats();
        expect((finalStats['writes'] as List), hasLength(9));
        expect(finalStats['confirmed'], 1);
        expect(finalStats['explorer_confirmed'], 160);
        expect(finalStats['ledger'], [
          {'actual': 7, 'source_type': 'task'},
        ]);
        await File('${support.path}/mykids-quality116-server-stats.json')
            .writeAsString(jsonEncode(finalStats));
        await File('${support.path}/mykids-quality116-proof.json')
            .writeAsString(
              jsonEncode({
                'first_story_without_tasks': true,
                'real_parent_confirmation_unlocks_find': true,
                'pending_does_not_unlock': true,
                'riddle_hint_retry_and_success': true,
                'riddles_send_no_request_and_change_no_money': true,
                'five_styles_large_text': true,
                'saved_map_available_offline': true,
                'parent_can_disable_and_progress_survives': true,
                'stale_session_hidden': true,
                'covering_route_preserved': true,
                'tasks_navigation_working': true,
                'robot_routes_playable_from_start': true,
                'robot_route_replay_and_obstacles': true,
                'robot_games_send_no_requests_or_money': true,
                'new_worlds_from_confirmed_history': true,
                'robot_parent_control': true,
                'station_six_games_offline_from_start': true,
                'station_retry_peek_hint_replay': true,
                'station_parent_control_and_session_revocation': true,
                'station_covering_route_preserved': true,
                'physical_phone': false,
              }),
            );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await repo.logout(remote: false);
        await repo.db?.close();
        repo.client.close();
        control.close();
        repo.dispose();
        page.dispose();
      }
    },
  );
}
