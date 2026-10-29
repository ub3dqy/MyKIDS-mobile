import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/invitation.dart';
import 'package:mykids_family/invitation_scanner.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/visuals.dart';
import 'package:mykids_family/voice_note.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:workmanager/workmanager.dart';

// Deterministic silence exercises private-file ownership without using a host
// microphone. The scanner below uses Android's actual emulated camera/decoder.
class SilentCapture implements VoiceCapture {
  final changes = StreamController<RecordState>.broadcast();
  String? path;
  bool recording = false;
  @override
  Stream<RecordState> get states => changes.stream;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start(String path) async {
    this.path = path;
    final data = Uint8List(32044);
    final header = ByteData.sublistView(data);
    data.setRange(0, 4, ascii.encode('RIFF'));
    header.setUint32(4, data.length - 8, Endian.little);
    data.setRange(8, 16, ascii.encode('WAVEfmt '));
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 32000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    data.setRange(36, 40, ascii.encode('data'));
    header.setUint32(40, data.length - 44, Endian.little);
    await File(path).writeAsBytes(data, flush: true);
    recording = true;
    changes.add(RecordState.record);
  }

  @override
  Future<String?> stop() async {
    recording = false;
    changes.add(RecordState.stop);
    return path;
  }

  @override
  Future<void> cancel() async => recording = false;
  @override
  Future<bool> isRecording() async => recording;
  @override
  Future<bool> isPaused() async => false;
  @override
  Future<void> close() async {
    recording = false;
    await changes.close();
  }
}

class ChatWire extends http.BaseClient {
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
  testWidgets('owned Android chat exit and invitation camera', (tester) async {
    final guest = await Process.run('/system/bin/getprop', ['ro.kernel.qemu']);
    expect(Platform.isAndroid && guest.stdout.toString().trim() == '1', true);
    HttpOverrides.global = null;
    const endpoint = 'http://127.0.0.1:18808';
    final support = await getApplicationSupportDirectory();
    final wire = ChatWire();
    final repo = FamilyRepository(client: wire);
    final control = http.Client();
    final navigator = GlobalKey<NavigatorState>();
    final captures = <SilentCapture>[];
    double? scale;
    var revision = 0;

    Future<void> until(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) fail('Native state absent');
        await tester.pump(const Duration(milliseconds: 150));
      }
      await tester.pumpAndSettle();
    }

    Future<void> stage(String name) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await File('${support.path}/mykids-quality119-stage.json')
          .writeAsString(jsonEncode({'stage': name}));
      final ack = File('${support.path}/mykids-quality119-continue-$name');
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!await ack.exists()) {
        if (DateTime.now().isAfter(deadline)) fail('Capture timed out: $name');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await ack.delete();
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().isNotEmpty);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target.hitTestable());
      await tester.pumpAndSettle();
    }

    Future<void> login(String name) async {
      await repo.login(
        endpoint,
        'quality119-$name',
        'synthetic-native-chat-119',
      );
      await tester.pumpAndSettle();
    }

    Future<void> mount() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(revision++),
          navigatorKey: navigator,
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: familyTheme(false),
          builder: (context, child) => scale == null
              ? child!
              : MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
          home: const Scaffold(
            body: Center(child: Text('Список семейных чатов')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<SilentCapture> chat() async {
      final capture = SilentCapture();
      captures.add(capture);
      final room = repo.rows('rooms').firstWhere((r) => r['kind'] == 'family');
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ChatScreen(repository: repo, room: room, voiceCapture: capture),
          ),
        ),
      );
      await until(
        () => find
            .text('Лучик готов к семейной экспедиции!')
            .evaluate()
            .isNotEmpty,
      );
      return capture;
    }

    Future<void> draft(SilentCapture capture) async {
      await tap(find.byTooltip('Голосовое'));
      await until(() => capture.recording);
      await tap(find.byTooltip('Остановить запись'));
      await until(() => find.text('Запись готова').evaluate().isNotEmpty);
      expect(await File(capture.path!).exists(), true);
    }

    Future<void> decision() async {
      unawaited(navigator.currentState!.maybePop());
      await until(
        () => find.text('Удалить голосовую запись?').evaluate().isNotEmpty,
      );
    }

    Future<void> cover() async {
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Другой важный экран')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<Map<String, dynamic>> stats() async {
      final response = await control.get(
        Uri.parse('$endpoint/quality119/stats'),
        headers: {'X-MyKIDS-QA': 'quality119-loopback-only'},
      );
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    try {
      await Workmanager().initialize(backgroundSync);
      await repo.initialize();
      await login('child');
      for (final design in GameDesign.all) {
        gameDesign.value = design;
        await mount();
        final capture = await chat();
        await stage('chat-style-${design.id}');
        expect(capture.recording, false);
      }

      gameDesign.value = GameDesign.byId('islands');
      await mount();
      final kept = await chat();
      await draft(kept);
      await decision();
      await stage('chat-draft-decision');
      final staleDelete = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Удалить и выйти'),
          )
          .onPressed!;
      await cover();
      staleDelete();
      await tester.pumpAndSettle();
      expect(find.text('Другой важный экран'), findsOneWidget);
      expect(await File(kept.path!).exists(), true);
      await stage('chat-cover-preserved');
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tap(find.text('Остаться'));
      expect(find.text('Запись готова'), findsOneWidget);
      expect(await File(kept.path!).exists(), true);
      await stage('chat-draft-kept');

      wire.offline = true;
      await repo.sync();
      expect(repo.online, false);
      await decision();
      await stage('chat-offline-decision');
      await tap(find.text('Удалить и выйти'));
      await until(() => find.byType(ChatScreen).evaluate().isEmpty);
      expect(await File(kept.path!).exists(), false);
      await stage('chat-draft-deleted');
      wire.offline = false;
      await repo.sync();
      expect(repo.online, true);

      await mount();
      final obsolete = await chat();
      await draft(obsolete);
      await decision();
      final oldDecision = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Удалить и выйти'),
          )
          .onPressed!;
      await login('parent');
      oldDecision();
      await tester.pumpAndSettle();
      expect(find.text('Нужно открыть окно заново'), findsOneWidget);
      await stage('chat-old-owner-blocked');
      await tap(find.text('Закрыть'));
      await until(() => find.byType(ChatScreen).evaluate().isEmpty);
      expect(await File(obsolete.path!).exists(), false);
      final inviteReply = await repo.mutate('/v1/invites', {'role': 'child'});
      final invite = Invitation(
        role: 'child',
        token: inviteReply['token'] as String,
      );
      await login('child');

      scale = 2;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
      ]);
      await until(
        () => tester.view.physicalSize.width > tester.view.physicalSize.height,
      );
      await mount();
      final landscape = await chat();
      await draft(landscape);
      await decision();
      await stage('chat-large-landscape');
      await tap(find.text('Остаться'));
      await tap(find.byTooltip('Отменить запись'));
      await until(() => !File(landscape.path!).existsSync());
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await until(
        () => tester.view.physicalSize.height > tester.view.physicalSize.width,
      );
      scale = null;
      await mount();
      await chat();
      await tester.enterText(
        find.byType(TextField).last,
        'Проверочное семейное сообщение119',
      );
      await tap(find.byTooltip('Отправить'));
      await until(
        () => find
            .text('Проверочное семейное сообщение119')
            .evaluate()
            .isNotEmpty,
      );
      await stage('chat-message-sent');

      await mount();
      Invitation? scanned;
      unawaited(
        navigator.currentState!
            .push<Invitation>(
              MaterialPageRoute<Invitation>(
                builder: (_) => const InvitationScanner(role: 'child'),
              ),
            )
            .then((value) => scanned = value),
      );
      await until(() => find.byType(MobileScanner).evaluate().isNotEmpty);
      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      final camera = scanner.controller!;
      await until(() => camera.value.isRunning);
      await stage('scanner-running');
      final manual = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Ввести код вручную'),
          )
          .onPressed!;
      await cover();
      await until(() => !camera.value.isRunning && !camera.value.isStarting);
      manual();
      scanner.onDetect!(
        BarcodeCapture(barcodes: [Barcode(rawValue: invite.qrData)]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Другой важный экран'), findsOneWidget);
      expect(scanned, isNull);
      await stage('scanner-covered');
      navigator.currentState!.pop();
      await until(() => camera.value.isRunning);
      await stage('scanner-resumed');

      scanner.onDetect!(
        BarcodeCapture(
          barcodes: [
            Barcode(
              rawValue: Invitation(role: 'parent', token: 'w' * 43).qrData,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Это приглашение для родителей. Выберите эту роль'),
        findsOneWidget,
      );
      expect(scanned, isNull);
      await stage('scanner-wrong-role');
      final painter = QrPainter(
        data: invite.qrData,
        version: QrVersions.auto,
        gapless: true,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 832, 832),
          Paint()..color = Colors.white,
        )
        ..translate(32, 32);
      painter.paint(canvas, const Size.square(768));
      final picture = recorder.endRecording();
      final image = await picture.toImage(832, 832);
      picture.dispose();
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      image.dispose();
      final qr = File('${support.path}/quality119-synthetic-qr.png');
      await qr.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
      final decoded = await camera.analyzeImage(
        qr.path,
        formats: [BarcodeFormat.qrCode],
      );
      expect(decoded, isNotNull);
      expect(decoded!.barcodes.any((b) => b.rawValue == invite.qrData), true);
      scanner.onDetect!(decoded);
      await until(() => scanned != null);
      expect(scanned!.token, invite.token);
      expect(camera.value.isRunning, false);
      await qr.delete();
      await stage('scanner-matched-invitation');

      unawaited(
        navigator.currentState!.push<Invitation>(
          MaterialPageRoute<Invitation>(
            builder: (_) => const InvitationScanner(role: 'child'),
          ),
        ),
      );
      await until(() => find.byType(MobileScanner).evaluate().isNotEmpty);
      final second = tester
          .widget<MobileScanner>(find.byType(MobileScanner))
          .controller!;
      await until(() => second.value.isRunning);
      await tap(find.text('Ввести код вручную'));
      await until(() => find.byType(InvitationScanner).evaluate().isEmpty);
      // The SDK retains its last value after disposal. The host checks actual
      // Android camera clients at the following manual-entry capture instead.
      manual();
      expect(find.text('Список семейных чатов'), findsOneWidget);
      await stage('scanner-manual-entry');

      final finalStats = await stats();
      final writes = finalStats['writes'] as List;
      expect(writes.every((row) => row['status'] == 200), true);
      final business = writes
          .where((row) => !row['path'].toString().endsWith('/receipt'))
          .toList();
      expect(business.length, 2);
      expect(business.first['path'], '/v1/invites');
      expect(business.last['body'], {
        'text': 'Проверочное семейное сообщение119',
      });
      expect(finalStats['attachments'], 0);
      expect(finalStats['ledger'], 0);
      expect(finalStats['invites'], 1);
      expect((finalStats['messages'] as List).length, 2);
      expect(finalStats['real_families'], false);
      expect(tester.takeException(), isNull);
      await File('${support.path}/mykids-quality119-server-stats.json')
          .writeAsString(jsonEncode(finalStats));
      await File('${support.path}/mykids-quality119-proof.json').writeAsString(
        jsonEncode({
          'passed': true,
          'physical_phone': false,
          'large_text_and_five_styles': true,
          'chat_draft_keep_delete_offline': true,
          'chat_cover_preserved': true,
          'chat_old_owner_blocked': true,
          'chat_text_delivery': true,
          'scanner_camera_released_when_covered': true,
          'scanner_camera_resumes_when_visible': true,
          'scanner_old_manual_callback_blocked': true,
          'scanner_wrong_role_rejected': true,
          'native_decoder_reads_synthetic_qr': true,
          'scanner_matching_invitation_returns': true,
          'no_unsent_voice_uploads_or_money_changes': true,
        }),
      );
    } finally {
      wire.offline = false;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final capture in captures) {
        if (capture.path != null) {
          expect(await File(capture.path!).exists(), false);
        }
      }
      control.close();
      repo.client.close();
      repo.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
