import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;
import 'package:mykids_family/call_screen.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/updates.dart';
import 'package:mykids_family/visuals.dart';

class ProbeUpdates extends AppUpdates {
  @override
  Future<UpdateOffer?> check(Uri url, String role) async => null;
}

class ProbeRepository extends FamilyRepository {
  final Map<String, dynamic> access;
  Map<String, dynamic>? active;
  ProbeRepository(this.access) {
    variant = 'child';
    token = 'synthetic-unregistered-test';
    online = true;
    endpoint = 'http://10.0.2.2:18883';
    snapshot = {
      'user': {'id': 'child-probe', 'role': 'child', 'name': 'Проверка'},
      'family': {
        'timezone': 'Europe/Moscow',
        'day_start': '07:00',
        'day_end': '22:00',
        'quiet_start': '00:00',
        'quiet_end': '00:00',
      },
      'server_time': '2026-10-12T10:00:00Z',
      'balance': {'available': 125, 'total': 125, 'reserved': 0},
      'members': [
        {
          'id': 'parent-probe',
          'name': 'Проверочный папа',
          'role': 'parent',
          'active': 1,
        },
      ],
      'calls': [],
      'schedules': [],
      'schedule_exceptions': [],
      'tasks': [],
      'ledger': [],
      'rewards': [],
      'redemptions': [],
      'rooms': [],
    };
  }
  void invite(Map<String, dynamic> entry) {
    active = entry;
    snapshot!['calls'] = [
      {
        'id': entry['id'],
        'caller_id': 'parent-probe',
        'status': 'ringing',
        'member_status': 'invited',
        'video': entry['video'] == true ? 1 : 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    ];
    notifyListeners();
  }

  @override
  Future<void> sync() async {
    notifyListeners();
  }

  @override
  Future<List<Map<String, Object?>>> pending() async => [];
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    snapshot!['calls'][0]['member_status'] = body['action'] == 'join'
        ? 'joined'
        : 'left';
    snapshot!['calls'][0]['status'] = body['action'] == 'join'
        ? 'active'
        : 'ended';
    notifyListeners();
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/devices') {
      final result = await client.post(
        Uri.parse('$endpoint/device'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      expect(result.statusCode, 200);
      return {'ok': true};
    }
    if (path.endsWith('/token')) {
      return {
        'url': access['url'],
        'token': active!['token'],
        'video': active!['video'],
      };
    }
    throw StateError('Unexpected fixture request');
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'foreground invitation, Android audio/video media and automatic FCM registration',
    (tester) async {
      final response = await http.get(
        Uri.parse('http://10.0.2.2:18883/fixture'),
      );
      expect(response.statusCode, 200);
      final access = jsonDecode(response.body) as Map<String, dynamic>;
      final repo = ProbeRepository(access);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpWidget(
        MyKidsApp(
          repository: repo,
          createUpdates: ProbeUpdates.new,
          now: () => DateTime.utc(2026, 10, 12, 10),
        ),
      );
      await tester.runAsync(
        () => precacheFamilyArtwork(tester.element(find.byType(MyKidsApp))),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Твой день'), findsOneWidget);
      expect(find.text('Твои семейные монеты'), findsNothing);
      await tester.tap(find.byType(FamilyCoinButton));
      await tester.pump();
      expect(find.byType(MoneyScreen), findsOneWidget);
      await tester.tap(find.text('Сегодня'));
      await tester.pump();
      Future<void> screenshot(String name) async {
        var complete = false;
        final capture = binding.takeScreenshot(name)
          ..whenComplete(() => complete = true);
        for (var i = 0; i < 100 && !complete; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(complete, true);
        await capture;
      }

      await screenshot('today-compact-coins');
      final checks = <Map<String, Object>>[];
      for (final entry in (access['cases'] as List).cast<Map>()) {
        final video = entry['video'] == true;
        repo.invite(Map<String, dynamic>.from(entry));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text(video ? 'Входящий видеозвонок' : 'Входящий аудиозвонок'),
          findsOneWidget,
        );
        const messengerCheck = bool.fromEnvironment('MESSENGER_CALL_CHECK');
        await tester.tap(find.text('Ответить'));
        await tester.pump(const Duration(milliseconds: 300));
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        Room? room;
        num audioBytes = 0, videoFrames = 0;
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (find.byType(CallScreen).evaluate().isNotEmpty) {
            room =
                (tester.state(find.byType(CallScreen)) as dynamic).room as Room;
            for (final peer in room.remoteParticipants.values) {
              for (final pub in peer.audioTrackPublications) {
                if (pub.track is RemoteAudioTrack) {
                  audioBytes =
                      (await (pub.track as RemoteAudioTrack).getReceiverStats())
                          ?.bytesReceived ??
                      0;
                }
              }
              for (final pub in peer.videoTrackPublications) {
                if (pub.track is RemoteVideoTrack) {
                  videoFrames =
                      (await (pub.track as RemoteVideoTrack).getReceiverStats())
                          ?.framesDecoded ??
                      0;
                }
              }
            }
            if (audioBytes > 0 &&
                (!video || videoFrames >= 3) &&
                find.byTooltip('Выключить микрофон').evaluate().isNotEmpty &&
                (!video ||
                    find.byType(VideoTrackRenderer).evaluate().length >= 2) &&
                room.localParticipant?.audioTrackPublications.isNotEmpty ==
                    true &&
                (!video ||
                    room.localParticipant?.videoTrackPublications.isNotEmpty ==
                        true)) {
              break;
            }
          }
        }
        expect(audioBytes, greaterThan(0));
        if (video) expect(videoFrames, greaterThanOrEqualTo(3));
        expect(room!.localParticipant!.audioTrackPublications, isNotEmpty);
        expect(find.byTooltip('Выключить микрофон'), findsOneWidget);
        if (video) {
          expect(room.localParticipant!.videoTrackPublications, isNotEmpty);
          expect(find.byType(VideoTrackRenderer), findsNWidgets(2));
        }
        await tester.pump(const Duration(milliseconds: 300));
        await screenshot(
          video ? 'incoming-video-connected' : 'incoming-audio-connected',
        );
        if (messengerCheck) {
          await tester.tap(find.byTooltip('Выключить микрофон'));
          await tester.pumpAndSettle();
          expect(
            room.localParticipant!.audioTrackPublications.first.muted,
            true,
          );
          expect(find.byTooltip('Включить микрофон'), findsOneWidget);
          await tester.tap(find.byTooltip('Включить микрофон'));
          await tester.pumpAndSettle();
          expect(
            room.localParticipant!.audioTrackPublications.first.muted,
            false,
          );
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        await tester.ensureVisible(find.text('Завершить'));
        await tester.tap(find.text('Завершить'));
        for (
          var i = 0;
          i < 30 && find.byType(CallScreen).evaluate().isNotEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(find.byType(CallScreen), findsNothing);
        checks.add({
          'video': video,
          'incoming_presented': true,
          'remote_audio_bytes': audioBytes,
          'remote_video_frames': videoFrames,
          'local_media_published': true,
          'call_controls_visible': true,
          'video_renderers_present': video ? 2 : 0,
        });
      }
      final stats = jsonDecode(
        (await http.get(Uri.parse('${repo.endpoint}/metrics'))).body,
      ) as Map;
      expect(stats['device_registered'], true);
      final received = stats['received_from_android'] as List;
      expect(received[0]['audio'], greaterThanOrEqualTo(3));
      expect(received[1]['audio'], greaterThanOrEqualTo(3));
      expect(received[1]['video'], greaterThanOrEqualTo(3));
      await http.post(
        Uri.parse('${repo.endpoint}/done'),
        headers: {'Content-Type': 'application/json'},
        body: '{"passed":true}',
      );
      binding.reportData = {
        ...?binding.reportData,
        'cases': checks,
        'automatic_device_registration': true,
        'coins_header_opens_money': true,
        'coin_card_removed': true,
        'synthetic_only': true,
        'scope': 'Owned Android 16 emulator; synthetic public LiveKit peers; no physical phones; emulator microphone frames do not prove intelligible speech',
      };
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      repo.client.close();
      repo.dispose();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
