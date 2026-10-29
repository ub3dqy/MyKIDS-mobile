import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/voice_note.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/messenger_fixture.dart';

class AndroidCapture extends DeviceVoiceCapture {
  String? path;
  @override
  Future<void> start(String path) async {
    this.path = path;
    await super.start(path);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Android voice capture, retry and background stop', (
    tester,
  ) async {
    final emulator = await Process.run('/system/bin/getprop', [
      'ro.kernel.qemu',
    ]);
    expect(
      Platform.isAndroid && emulator.stdout.toString().trim() == '1',
      true,
    );
    final support = await getApplicationSupportDirectory();
    Future<void> stage(String value) =>
        File('${support.path}/mykids-quality101-stage.json')
            .writeAsString(jsonEncode({'stage': value}));
    final template = MessengerFixture();
    final snapshot =
        jsonDecode(jsonEncode(template.snapshot)) as Map<String, dynamic>;
    snapshot['calls'] = [];
    template.client.close();
    template.dispose();
    final messages = <Map<String, dynamic>>[];
    final serverErrors = <String>[];
    var uploads = 0, deliveries = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final listener = server.listen((request) async {
      try {
        final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        expectSync(body.length, lessThan(4 * 1024 * 1024));
        final path = request.uri.path;
        request.response.headers.contentType = ContentType.json;
        Object response = {};
        if (path == '/v1/login') {
          response = {'token': 'synthetic-android-voice'};
        } else {
          expectSync(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer synthetic-android-voice',
          );
          if (path == '/v1/snapshot') {
            response = snapshot;
          } else if (path == '/v1/rooms/private/messages' &&
              request.method == 'GET') {
            response = {'messages': messages, 'has_more': false};
          } else if (path == '/v1/attachments') {
            uploads++;
            expectSync(request.uri.queryParameters['context_type'], 'room');
            expectSync(request.uri.queryParameters['context_id'], 'private');
            final multipart = latin1.decode(body);
            final riff = multipart.indexOf('RIFF');
            expectSync(riff, greaterThan(0));
            expectSync(multipart.substring(riff + 8, riff + 12), 'WAVE');
            expectSync(body.length - riff, greaterThan(44));
            if (uploads == 1) {
              request.response.statusCode = 503;
              response = {'detail': 'Проверка: попробуйте отправить ещё раз'};
            } else {
              response = {'id': 'android-voice-attachment'};
            }
          } else if (path == '/v1/rooms/private/messages' &&
              request.method == 'POST') {
            final command = jsonDecode(utf8.decode(body)) as Map;
            expectSync(command['attachment_id'], 'android-voice-attachment');
            deliveries++;
            final message = <String, dynamic>{
              'id': 'android-message-$deliveries',
              'sender_id': 'child',
              'attachment_id': 'android-voice-attachment',
              'attachment_mime': 'audio/wav',
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'receipts': [],
              'text': '',
            };
            messages.add(message);
            response = message;
          } else if (path == '/v1/counters') {
            response = {'rooms': []};
          } else {
            throw StateError('Unexpected synthetic route: $path');
          }
        }
        request.response.write(jsonEncode(response));
        await request.response.close();
      } catch (e) {
        serverErrors.add(e.toString());
        request.response.statusCode = 500;
        request.response.write('{}');
        await request.response.close();
      }
    });
    final repo = FamilyRepository();
    final capture = AndroidCapture(), player = AudioPlayer();
    Future<void> waitUi(bool Function() condition) async {
      for (var i = 0; i < 150 && !condition(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(condition(), true);
    }

    Future<void> press(String label) async {
      final button = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == label,
      );
      await waitUi(
        () =>
            button.evaluate().length == 1 &&
            tester.widget<IconButton>(button).onPressed != null,
      );
      await tester.tap(button);
    }

    Future<void> screenshot(String name) async {
      final bytes = await binding.takeScreenshot('voice-$name');
      expect(bytes, isNotEmpty);
      await File('${support.path}/mykids-quality101-$name.png')
          .writeAsBytes(bytes);
    }

    try {
      await repo.initialize();
      await repo.login(
        'http://127.0.0.1:${server.port}',
        'synthetic',
        'local-only-password',
      );
      await repo.sync();
      expect(repo.online, true);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            repository: repo,
            room: repo.rows('rooms').firstWhere((r) => r['id'] == 'private'),
            voiceCapture: capture,
            audioPlayer: player,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await stage('permission');
      await press('Голосовое');
      await waitUi(
        () => find.byTooltip('Остановить запись').evaluate().isNotEmpty,
      );
      expect(await capture.recorder.isRecording(), true);
      await tester.pump(const Duration(seconds: 2));
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await screenshot('recording');
      await press('Остановить запись');
      await waitUi(
        () => find.byTooltip('Прослушать запись').evaluate().isNotEmpty,
      );
      final firstPath = capture.path!;
      final wav = await File(firstPath).readAsBytes();
      expect(wav.length, greaterThan(44));
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(await capture.recorder.isRecording(), false);
      expect(uploads, 0);
      await screenshot('draft');
      await press('Прослушать запись');
      await waitUi(
        () => player.playing && player.processingState == ProcessingState.ready,
      );
      await player.stop();
      await tester.pump();
      await press('Отправить запись');
      await waitUi(
        () => find
            .text('Проверка: попробуйте отправить ещё раз')
            .evaluate()
            .isNotEmpty,
      );
      expect(File(firstPath).existsSync(), true);
      expect(deliveries, 0);
      await screenshot('retry');
      await press('Отправить запись');
      await waitUi(
        () =>
            deliveries == 1 &&
            find.byTooltip('Голосовое').evaluate().isNotEmpty,
      );
      expect(uploads, 2);
      expect(File(firstPath).existsSync(), false);
      expect(await repo.db!.query('outbox'), isEmpty);
      await press('Голосовое');
      await waitUi(
        () => find.byTooltip('Остановить запись').evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(await capture.recorder.isRecording(), true);
      final backgroundPath = capture.path!;
      await stage('background-started');
      var nativeStopped = false;
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!await capture.recorder.isRecording()) {
          nativeStopped = true;
          break;
        }
      }
      expect(nativeStopped, true);
      await stage('background-stopped');
      for (
        var i = 0;
        i < 100 &&
            WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(WidgetsBinding.instance.lifecycleState, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Запись готова'), findsOneWidget);
      expect(uploads, 2);
      expect(deliveries, 1);
      await press('Отменить запись');
      await waitUi(() => find.byTooltip('Голосовое').evaluate().isNotEmpty);
      expect(File(backgroundPath).existsSync(), false);
      expect(serverErrors, isEmpty);
      binding.reportData = {
        ...?binding.reportData,
        'actual_android_recorder': true,
        'native_wav_bytes': wav.length,
        'native_wav_header_verified': true,
        'actual_android_playback_decoder': true,
        'real_android_http_upload': true,
        'failed_upload_preserves_recording': true,
        'retry_delivered_once': true,
        'actual_android_home_stops_microphone': true,
        'background_draft_not_sent': true,
        'cancel_deletes_private_draft': true,
        'synthetic_only': true,
        'physical_phone': false,
        'audio_acceptance': 'Emulator capture/decoder only; no physical microphone or audible quality acceptance.',
      };
    } catch (_) {
      await File('${support.path}/mykids-quality101-failure.json')
          .writeAsString(
            jsonEncode({
              'uploads': uploads,
              'deliveries': deliveries,
              'server_errors': serverErrors,
              'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
              'labels': tester
                  .widgetList<Text>(find.byType(Text))
                  .map((t) => t.data)
                  .whereType<String>()
                  .toList(),
            }),
          );
      rethrow;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.logout(remote: false);
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
      await listener.cancel();
      await server.close(force: true);
    }
    final report = Map<String, dynamic>.from(binding.reportData!)
      ..remove('screenshots');
    await File('${support.path}/mykids-quality101-proof.json')
        .writeAsString(jsonEncode(report));
    await stage('complete');
  });
}
