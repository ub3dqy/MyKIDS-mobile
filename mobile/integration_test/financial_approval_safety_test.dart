import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:uuid/uuid.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual Android parental consent against isolated real API', (
    tester,
  ) async {
    final emulator = await Process.run('/system/bin/getprop', [
      'ro.kernel.qemu',
    ]);
    expect(
      Platform.isAndroid && emulator.stdout.toString().trim() == '1',
      true,
    );
    tzdata.initializeTimeZones();
    HttpOverrides.global = null;
    const endpoint = 'http://127.0.0.1:18803';
    const password = 'synthetic-native-financial-123';
    final support = await getApplicationSupportDirectory();
    final transport = http.Client();
    final login = await transport.post(
      Uri.parse('$endpoint/v1/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': 'quality103-relative',
        'password': password,
      }),
    );
    expect(login.statusCode, 200);
    final relative = (jsonDecode(login.body) as Map)['token'] as String;
    Future<Map<String, dynamic>> command(
      String path,
      Map<String, dynamic> data, {
      String method = 'POST',
    }) async {
      final request = http.Request(method, Uri.parse('$endpoint$path'))
        ..headers.addAll({
          'Authorization': 'Bearer $relative',
          'Content-Type': 'application/json',
          'Idempotency-Key': const Uuid().v4(),
        })
        ..body = jsonEncode(data);
      final response = await http.Response.fromStream(
        await transport.send(request),
      );
      expect(response.statusCode, 200, reason: response.body);
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }

    final created = await command('/v1/tasks', {
      'title': 'Проверочная награда',
      'reward': 30,
      'penalty': 15,
      'is_required': true,
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'due_at': DateTime.now()
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
    });
    final ids = (created['ids'] as List).cast<String>();
    final repo = FamilyRepository();
    await repo.initialize();
    await repo.selectRole('parent');
    await repo.login(endpoint, 'quality103-parent', password);
    Map<String, dynamic> task(String id) =>
        repo.rows('tasks').singleWhere((t) => t['id'] == id);
    Future<void> edit(String id, int reward) async {
      final value = task(id);
      await command('/v1/tasks/$id', {
        for (final k in [
          'title',
          'description',
          'due_at',
          'penalty',
          'reviewer_id',
          'program_id',
          'subject_id',
          'planned_start',
          'planned_end',
          'reminder_minutes',
          'reward_options',
          'required_photos',
        ])
          k: value[k],
        'reward': reward,
        'is_required': value['is_required'] == 1,
        'require_photo': value['require_photo'] == 1,
        'task_version': value['version'],
      }, method: 'PUT');
      await repo.sync();
    }

    Future<void> open(String id) async {
      // Each visit starts as a new route, without the previous card's scroll offset.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskScreen(
              key: ValueKey(id),
              repository: repo,
              focusTaskId: id,
              perform: (action) async {
                await action();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text('Проверочная награда');
      await tester.ensureVisible(title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      final button = find.text('Согласовать награду и штраф');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    Future<void> ownerScreenshot(String name) async {
      final ready = File('${support.path}/mykids-quality103-stage.json');
      final signal = File('${support.path}/mykids-quality103-continue-$name');
      await ready.writeAsString(jsonEncode({'stage': name}));
      final limit = DateTime.now().add(const Duration(seconds: 90));
      while (!await signal.exists()) {
        if (DateTime.now().isAfter(limit)) {
          fail('Owned screenshot coordinator did not acknowledge $name');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await signal.delete();
    }

    Future<void> confirm(String id) async {
      final button = find.byKey(const ValueKey('confirm-task-finances'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      for (var n = 0; n < 100 && task(id)['financial_approved'] != 1; n++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(task(id)['financial_approved'], 1);
      await tester.pumpAndSettle();
    }

    Future<void> nativeVideo() async {
      final sender = await rtc.createPeerConnection({
        'iceServers': [],
        'sdpSemantics': 'unified-plan',
      });
      final receiver = await rtc.createPeerConnection({
        'iceServers': [],
        'sdpSemantics': 'unified-plan',
      });
      final renderer = rtc.RTCVideoRenderer();
      await renderer.initialize();
      final outbound = <rtc.RTCIceCandidate>[],
          inbound = <rtc.RTCIceCandidate>[];
      sender.onIceCandidate = (candidate) {
        if (candidate.candidate?.isNotEmpty == true) {
          outbound.add(candidate);
        }
      };
      receiver.onIceCandidate = (candidate) {
        if (candidate.candidate?.isNotEmpty == true) {
          inbound.add(candidate);
        }
      };
      receiver.onTrack = (event) {
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          renderer.srcObject = event.streams.first;
        }
      };
      // The coordinator verifies hw.camera.back=emulated. No audio is requested.
      final stream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'environment',
          'width': 320,
          'height': 240,
          'frameRate': 10,
        },
      });
      try {
        for (final track in stream.getVideoTracks()) {
          await sender.addTrack(track, stream);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Проверочное видео эмулятора')),
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 240,
                  child: ValueListenableBuilder(
                    valueListenable: renderer,
                    builder: (context, value, child) =>
                        rtc.RTCVideoView(renderer),
                  ),
                ),
              ),
            ),
          ),
        );
        final offer = await sender.createOffer();
        await sender.setLocalDescription(offer);
        await receiver.setRemoteDescription(offer);
        final answer = await receiver.createAnswer();
        await receiver.setLocalDescription(answer);
        await sender.setRemoteDescription(answer);
        Future<int> frames() async => (await receiver.getStats())
            .where((s) => s.type == 'inbound-rtp')
            .fold<int>(
              0,
              (n, s) =>
                  n + (int.tryParse('${s.values['framesDecoded'] ?? 0}') ?? 0),
            );
        var before = 0;
        for (var n = 0; n < 200; n++) {
          while (outbound.isNotEmpty) {
            await receiver.addCandidate(outbound.removeAt(0));
          }
          while (inbound.isNotEmpty) {
            await sender.addCandidate(inbound.removeAt(0));
          }
          await tester.pump(const Duration(milliseconds: 100));
          before = await frames();
          if (before > 0 &&
              renderer.videoWidth > 0 &&
              renderer.videoHeight > 0) {
            break;
          }
        }
        expect(before, greaterThan(0));
        expect(await receiver.getTransceivers(), isNotEmpty);
        await tester.pump(const Duration(seconds: 2));
        final after = await frames();
        expect(after, greaterThan(before));
        expect(renderer.videoWidth, greaterThan(0));
        expect(renderer.videoHeight, greaterThan(0));
        await tester.pumpAndSettle();
        expect(find.byType(Texture), findsOneWidget);
        await ownerScreenshot('webrtc');
        await File('${support.path}/mykids-quality103-webrtc.json')
            .writeAsString(
              jsonEncode({
                'frames_before_transceivers': before,
                'frames_after_transceivers': after,
                'remote_width': renderer.videoWidth,
                'remote_height': renderer.videoHeight,
                'ice_servers': [],
                'audio_requested': false,
                'emulator_camera_only': true,
                'actual_native_peer_video': true,
                'flutter_texture_present': true,
                'physical_phone': false,
              }),
            );
      } finally {
        renderer.srcObject = null;
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await sender.dispose();
        await receiver.dispose();
        await stream.dispose();
        await renderer.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }

    try {
      await nativeVideo();
      await edit(ids[1], 1000000);
      await open(ids.first);
      expect(find.textContaining('включая будущие'), findsOneWidget);
      await ownerScreenshot('repeat');
      await confirm(ids.first);
      expect(task(ids[1])['financial_approved'], 0);
      expect(repo.snapshot!['balance']['total'], 0);
      await open(ids[1]);
      expect(find.textContaining('только этого задания'), findsOneWidget);
      await ownerScreenshot('single');
      await edit(ids[1], 75);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirm-task-finances')), findsNothing);
      expect(find.textContaining('Условия задания изменились'), findsOneWidget);
      await ownerScreenshot('changed');
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      await open(ids[1]);
      await confirm(ids[1]);
      expect(task(ids[2])['financial_approved'], 1);
      expect(repo.snapshot!['balance']['total'], 0);
      expect(repo.rows('ledger'), isEmpty);
      expect(await repo.pending(), isEmpty);
      await edit(ids[1], 90);
      await open(ids[1]);
      await repo.logout();
      await tester.pumpAndSettle();
      expect(
        find.text('Семейный доступ изменился. Закройте это окно.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('confirm-task-finances')), findsNothing);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      final proof = {
        'actual_android': true,
        'actual_native_webrtc_video': true,
        'actual_backend_http': true,
        'repeat_override_unapproved': true,
        'explicit_single_consent': true,
        'consent_alone_balance_unchanged': true,
        'stale_dialog_blocked': true,
        'session_change_hides_terms': true,
        'actual_private_queue_empty': true,
        'synthetic_only': true,
        'physical_phone': false,
      };
      await File('${support.path}/mykids-quality103-proof.json')
          .writeAsString(jsonEncode(proof));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
      transport.close();
    }
  });
}
