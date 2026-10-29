import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/design_today.dart';
import 'package:mykids_family/engagement/discovery_page.dart';
import 'package:mykids_family/engagement/engagement_scope.dart';
import 'package:mykids_family/engagement/production_controller.dart';
import 'package:mykids_family/engagement/ray_raid_controls.dart';
import 'package:mykids_family/engagement/ray_raid_game.dart';
import 'package:mykids_family/engagement/ray_raid_model.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/visuals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:workmanager/workmanager.dart';

import '../test/support/ray_raid_pilot.dart';

class RaidOfflineWire extends http.BaseClient {
  final inner = http.Client();
  bool offline = false;
  int attempted = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    attempted++;
    if (offline) throw const SocketException('Synthetic raid offline');
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
    'nine missions through ordinary multi-touch, real owner control and offline play',
    (tester) async {
      final emulator = await Process.run('/system/bin/getprop', [
        'ro.kernel.qemu',
      ]);
      expect(
        Platform.isAndroid && emulator.stdout.toString().trim() == '1',
        true,
      );
      HttpOverrides.global = null;
      tzdata.initializeTimeZones();
      await Workmanager().initialize(backgroundSync);
      const endpoint = 'http://127.0.0.1:18805';
      final support = await getApplicationSupportDirectory();
      final wire = RaidOfflineWire();
      final repo = FamilyRepository(client: wire);
      final controller = ProductionEngagementController(repo);
      final timings = <FrameTiming>[];
      void measure(List<FrameTiming> rows) => timings.addAll(rows);
      binding.addTimingsCallback(measure);
      Future<Map<String, dynamic>> stats() async {
        final response = await http.get(
          Uri.parse('$endpoint/quality116/stats'),
          headers: {'X-MyKIDS-QA': 'quality116-loopback-only'},
        );
        expect(response.statusCode, 200);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      Future<void> stage(String name) async {
        await tester.pump(const Duration(milliseconds: 150));
        await File('${support.path}/mykids-quality116-raid-stage.json')
            .writeAsString(jsonEncode({'stage': name}));
        final ack = File(
          '${support.path}/mykids-quality116-raid-continue-$name',
        );
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (!await ack.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Raid coordinator timed out: $name');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await ack.delete();
      }

      Finder keyed(String key) => find.byKey(ValueKey(key));
      Future<void> tap(String key) async {
        final finder = keyed(key);
        await tester.ensureVisible(finder);
        await tester.pump();
        expect(finder.hitTestable(), findsOneWidget);
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 40));
      }

      RayRaidWorld world() =>
          (tester.state(
                find.byType(RayRaidGame, skipOffstage: false),
              ) as dynamic).world
              as RayRaidWorld;
      Finder stick(String label) =>
          find.byWidgetPredicate((w) => w is RaidStick && w.label == label);
      Future<void> settled() async {
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
      }

      try {
        await repo.initialize();
        await repo.login(
          endpoint,
          'quality116-outside-child',
          'synthetic-native-expedition-123',
        );
        expect(controller.completedCount, 0);
        expect(repo.snapshot!['balance']['total'], 0);
        await tester.pumpWidget(
          EngagementScope(
            controller: controller,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('ru'),
              supportedLocales: const [Locale('ru')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: familyTheme(true),
              home: Scaffold(
                body: GameToday(repository: repo, openPage: (_) {}),
              ),
            ),
          ),
        );
        await settled();
        await tester.tap(find.text('Космос'));
        await settled();
        final entry = keyed('ray-raid-entry');
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await settled();
        expect(find.byType(RayRaidPage), findsOneWidget);
        expect(keyed('raid-scene'), findsOneWidget);
        await stage('raid-intro');
        final before = await stats();
        final requestsBeforeFlight = wire.attempted;
        wire.offline = true;
        repo.online = false;
        repo.notifyListeners();
        await tap('raid-start');
        await stage('raid-arena');
        await tap('raid-pause');
        final timeAtPause = world().elapsed;
        await tester.pump(const Duration(milliseconds: 600));
        expect(world().elapsed, timeAtPause);
        await tap('raid-resume');

        final oldDash = tester
            .widget<RaidAbilityButton>(keyed('raid-dash'))
            .onPressed;
        final nav = Navigator.of(tester.element(find.byType(RayRaidPage)));
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Другой экран')),
            ),
          ),
        );
        await settled();
        oldDash();
        expect(world().paused, true);
        expect(world().dashUses, 0);
        await stage('raid-covered');
        nav.pop();
        await settled();
        expect(world().paused, true);
        await tap('raid-resume');
        await stage('raid-background');
        for (
          var i = 0;
          i < 100 && keyed('raid-resume').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(keyed('raid-resume'), findsOneWidget);
        expect(world().paused, true);
        expect(world().movement.length, 0);
        expect(world().firing, false);
        await tap('raid-resume');

        final pilot = RaidPilot();
        final runs = <Map<String, Object>>[];
        for (final mission in RaidMission.values) {
          if (mission != RaidMission.beacon) {
            await tap('raid-next-mission');
            expect(world().mission, mission);
            expect(world().phase, RaidPhase.ready);
            await stage('raid-${mission.name}-intro');
            await tap('raid-start');
            await stage('raid-${mission.name}-arena');
          }
          TestGesture? move, fire;
          final choices = <String>[];
          final kinds = <String>{};
          final modules = switch (mission) {
            RaidMission.beacon => ['pulse', 'shield', 'dash'],
            RaidMission.foundry => ['companion', 'pulse', 'shield'],
            RaidMission.dock => ['pierce', 'companion', 'pulse'],
            RaidMission.convoy => ['frost', 'chain', 'shield'],
            RaidMission.storm => ['chain', 'pulse', 'frost'],
            RaidMission.portal => ['reflect', 'shock', 'pulse'],
            RaidMission.magnet => ['shock', 'reflect', 'pulse'],
            RaidMission.rescue => ['orbit', 'ricochet', 'pulse'],
            RaidMission.meteor => ['ricochet', 'orbit', 'pulse'],
          };
          var capturedSpecial = false;
          var maxBolts = 0, maxDrones = 0, maxParticles = 0, moves = 0;
          final start = world().player;
          final deadline = DateTime.now().add(const Duration(minutes: 4));
          while (world().phase != RaidPhase.won &&
              world().phase != RaidPhase.lost) {
            if (DateTime.now().isAfter(deadline)) {
              fail(
                'Ordinary touch pilot did not finish ${mission.name}: ${world().objective} hp${world().health}',
              );
            }
            kinds.addAll(world().drones.map((d) => d.kind.name));
            if (!capturedSpecial &&
                mission == RaidMission.convoy &&
                world().coreUnlocked &&
                !world().convoyAtStop) {
              await stage('raid-convoy-escort');
              capturedSpecial = true;
            }
            if (!capturedSpecial &&
                mission == RaidMission.portal &&
                world().portalHops == 1) {
              await stage('raid-portal-hop');
              capturedSpecial = true;
            }
            if (!capturedSpecial &&
                mission == RaidMission.magnet &&
                world().conveyorSteps > 15) {
              await stage('raid-magnet-belt');
              capturedSpecial = true;
            }
            if (!capturedSpecial &&
                mission == RaidMission.storm &&
                world().antennaCharge[0] > .2 &&
                world().antennaCharge[0] < 3.5) {
              await stage('raid-storm-capture');
              capturedSpecial = true;
            }
            if (!capturedSpecial &&
                mission == RaidMission.rescue &&
                world().carriedRescue != null) {
              await stage('raid-rescue-carry');
              capturedSpecial = true;
            }
            if (!capturedSpecial &&
                mission == RaidMission.meteor &&
                world().meteors.any((m) => m.delay > .15 && m.delay < 1.2)) {
              await stage('raid-meteor-warning');
              capturedSpecial = true;
            }
            if (world().phase == RaidPhase.upgrade) {
              await move?.up();
              await fire?.up();
              move = null;
              fire = null;
              final name = modules[world().coreCount - 1];
              choices.add(name);
              if (mission == RaidMission.beacon) {
                await stage('raid-upgrade-${world().coreCount}');
              } else if (world().coreCount == 1) {
                await stage('raid-${mission.name}-upgrade');
              }
              if ((mission == RaidMission.rescue && name == 'orbit') ||
                  (mission == RaidMission.meteor && name == 'ricochet')) {
                await tester.ensureVisible(keyed('raid-upgrade-$name'));
                await tester.pump(const Duration(milliseconds: 150));
                await stage('raid-${mission.name}-$name-choice');
              }
              await tap('raid-upgrade-$name');
              continue;
            }
            final center = tester.getCenter(stick('Движение'));
            move ??= await tester.startGesture(center, pointer: 1001);
            fire ??= await tester.startGesture(
              tester.getCenter(stick('Огонь')),
              pointer: 1002,
            );
            final direction = pilot.movement(world());
            final range = tester.getSize(stick('Движение')).width * .3;
            await move.moveTo(
              center + Offset(direction.x, direction.y) * range,
            );
            final shotAim = pilot.fireAim(world());
            await fire.moveTo(
              tester.getCenter(stick('Огонь')) +
                  Offset(shotAim.x, shotAim.y) *
                      tester.getSize(stick('Огонь')).width *
                      .3,
            );
            final danger = pilot.danger(world());
            if (danger && world().shieldCooldown == 0) await tap('raid-shield');
            if (pilot.shouldDash(world())) {
              await tap('raid-dash');
            }
            maxBolts = maxBolts < world().bolts.length
                ? world().bolts.length
                : maxBolts;
            maxDrones = maxDrones < world().drones.length
                ? world().drones.length
                : maxDrones;
            maxParticles = maxParticles < world().particles.length
                ? world().particles.length
                : maxParticles;
            moves++;
            await tester.pump(const Duration(milliseconds: 100));
          }
          await move?.up();
          await fire?.up();
          expect(
            world().phase,
            RaidPhase.won,
            reason:
                '${mission.name}: ${world().objective} hp${world().health}, ${world().elapsed}s',
          );
          expect(choices, modules);
          expect(world().disabledDrones, 17);
          expect(world().relaysDisabled, mission == RaidMission.dock ? 4 : 0);
          expect(world().moduleCount, 3);
          expect(world().player.distance(start), greaterThan(500));
          if (mission == RaidMission.foundry || mission == RaidMission.dock) {
            expect(kinds, containsAll(['interceptor', 'repairer']));
          }
          if (mission == RaidMission.convoy || mission == RaidMission.storm) {
            expect(capturedSpecial, true);
            expect(kinds, containsAll(['prism', 'bomber']));
            expect(world().beamAttacks, greaterThan(0));
            expect(world().blastAttacks, greaterThan(0));
          }
          if (mission == RaidMission.convoy) {
            expect(world().convoy.health, greaterThan(0));
            expect(world().convoy.position.distance(raidBeacon), lessThan(45));
          }
          if (mission == RaidMission.storm) {
            expect(world().antennaCharge, everyElement(4));
          }
          if (mission == RaidMission.portal || mission == RaidMission.magnet) {
            expect(capturedSpecial, true);
            expect(kinds, containsAll(['bulwark', 'boomerang']));
            expect(world().returnAttacks, greaterThan(0));
            expect(world().returnTurns, greaterThan(0));
          }
          if (mission == RaidMission.portal) expect(world().portalHops, 3);
          if (mission == RaidMission.magnet) {
            expect(world().conveyorSteps, greaterThan(0));
          }
          if (mission == RaidMission.rescue || mission == RaidMission.meteor) {
            expect(capturedSpecial, true);
            expect(kinds, containsAll(['pulsar', 'hopper']));
            expect(world().pulseAttacks, greaterThan(0));
            expect(world().jumpAttacks, greaterThan(0));
            expect(world().jumpLandings, greaterThan(0));
            expect(world().ricochetBounces, greaterThan(0));
          }
          if (mission == RaidMission.rescue) {
            expect(world().rescuedBots, {0, 1, 2});
            expect(world().rescuePickups, 3);
            expect(world().carriedRescue, isNull);
          }
          if (mission == RaidMission.meteor) {
            expect(world().meteorStrikes, greaterThan(0));
          }
          await stage(
            mission == RaidMission.beacon
                ? 'raid-victory'
                : 'raid-${mission.name}-victory',
          );
          runs.add({
            'mission': mission.name,
            'seconds': world().elapsed,
            'hull': world().health,
            'disabled_drones': world().disabledDrones,
            'relays_disabled': world().relaysDisabled,
            'repairs': world().repairedPulses,
            'encountered_kinds': kinds.toList()..sort(),
            'upgrades': choices,
            'shield_uses': world().shieldUses,
            'dash_uses': world().dashUses,
            'touch_updates': moves,
            'max_projectiles': maxBolts,
            'max_drones': maxDrones,
            'max_particles': maxParticles,
            'cargo_hull': world().convoy.health,
            'antenna_charge': List<double>.of(world().antennaCharge),
            'beam_attacks': world().beamAttacks,
            'blast_attacks': world().blastAttacks,
            'chain_hits': world().chainHits,
            'frost_steps': world().frostSteps,
            'portal_hops': world().portalHops,
            'conveyor_steps': world().conveyorSteps,
            'return_attacks': world().returnAttacks,
            'return_turns': world().returnTurns,
            'reflected_bolts': world().reflectedBolts,
            'shock_hits': world().shockHits,
            'rescued_bots': world().rescuedBots.toList()..sort(),
            'rescue_pickups': world().rescuePickups,
            'meteor_warnings': world().meteorWarnings,
            'meteor_strikes': world().meteorStrikes,
            'meteor_drone_hits': world().meteorDroneHits,
            'pulse_attacks': world().pulseAttacks,
            'jump_attacks': world().jumpAttacks,
            'jump_landings': world().jumpLandings,
            'ricochet_bounces': world().ricochetBounces,
            'orbit_blocks': world().orbitBlocks,
          });
        }
        expect(
          runs.expand((r) => r['upgrades'] as List<String>).toSet(),
          RaidUpgrade.values.map((u) => u.name).toSet(),
        );
        expect(runs.any((r) => (r['reflected_bolts'] as int) > 0), true);
        expect(runs.any((r) => (r['shock_hits'] as int) > 0), true);
        expect(runs.any((r) => (r['orbit_blocks'] as int) > 0), true);
        final after = await stats();
        expect(wire.attempted, requestsBeforeFlight);
        expect(after['requests'], before['requests']);
        expect(after['writes'], before['writes']);
        expect(after['ledger'], before['ledger']);
        expect(repo.snapshot!['balance']['total'], 0);
        expect(controller.completedCount, 0);
        final run = runs.first;
        await tap('raid-replay');
        expect(world().coreCount, 0);
        expect(world().moduleCount, 0);
        expect(world().health, 6);
        await tap('raid-pause');
        await stage('raid-replay');
        await tap('raid-exit');
        await settled();
        expect(find.byType(DiscoveryPage), findsOneWidget);

        wire.offline = false;
        repo.online = true;
        await tester.tap(keyed('ray-raid-entry'));
        await settled();
        await tap('raid-mission-convoy');
        await tap('raid-start');
        final stale = tester
            .widget<RaidAbilityButton>(keyed('raid-dash'))
            .onPressed;
        final login = await http.post(
          Uri.parse('$endpoint/v1/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': 'quality116-outside',
            'password': 'synthetic-native-expedition-123',
          }),
        );
        expect(login.statusCode, 200);
        final headers = {
          'Authorization': 'Bearer ${(jsonDecode(login.body) as Map)['token']}',
          'Content-Type': 'application/json',
        };
        final parentSnapshot = await http.get(
          Uri.parse('$endpoint/v1/snapshot'),
          headers: headers,
        );
        final engagement =
            ((jsonDecode(parentSnapshot.body) as Map)['engagement'] as List)
                    .single
                as Map;
        final disabled = await http.post(
          Uri.parse(
            '$endpoint/v1/engagement/${engagement['child_id']}/commands',
          ),
          headers: {...headers, 'Idempotency-Key': 'quality116-raid-disable'},
          body: jsonEncode({
            'action': 'set_enabled',
            'feature': 'adventure',
            'value': false,
            'expected_revision': engagement['revision'],
          }),
        );
        expect(disabled.statusCode, 200, reason: disabled.body);
        await repo.refreshAfterChange();
        await settled();
        stale();
        await tester.pump();
        expect(find.byType(RayRaidGame), findsNothing);
        expect(find.textContaining('Доступ изменился.'), findsOneWidget);
        await stage('raid-disabled');
        final percentiles = <String, Object>{};
        for (final category in ['build', 'raster']) {
          final rows =
              timings
                  .map(
                    (f) =>
                        (category == 'build'
                                ? f.buildDuration
                                : f.rasterDuration)
                            .inMicroseconds /
                        1000,
                  )
                  .toList()
                ..sort();
          expect(rows.length, greaterThan(100));
          percentiles[category] = {
            'frames': rows.length,
            'p50_ms': rows[(rows.length * .5).floor()],
            'p95_ms': rows[(rows.length * .95).floor()],
            'max_ms': rows.last,
          };
        }
        final proof = {
          'passed': true,
          'physical_phone': false,
          'ordinary_multi_touch_complete_run': true,
          'read_only_pilot_no_world_mutation': true,
          'three_upgrade_choices': true,
          'offline_no_requests_no_family_money': true,
          'zero_tasks_entry': true,
          'pause_freezes_combat': true,
          'route_cover_and_stale_control_blocked': true,
          'actual_android_background_requires_resume': true,
          'parent_revocation_hides_run': true,
          'replay_and_exit_usable': true,
          'run': run,
          'missions': runs,
          'all_nine_missions_completed': true,
          'all_new_modules_selected': true,
          'debug_emulator_frame_timings': percentiles,
        };
        await File('${support.path}/mykids-quality116-raid-proof.json')
            .writeAsString(jsonEncode(proof));
      } finally {
        binding.removeTimingsCallback(measure);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        repo.client.close();
        repo.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 32)),
  );
}
