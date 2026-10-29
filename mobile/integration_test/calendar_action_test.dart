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
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/invitation.dart';
import 'package:mykids_family/invitation_scanner.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';
import 'package:mykids_family/voice_note.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:workmanager/workmanager.dart';

// Keep deterministic connection loss in this foreground test. Android still
// stores real scheduled work; delivery is explicitly exercised by repo.sync().
// Background delivery on a locked physical device is outside this test.
@pragma('vm:entry-point')
void submissionTestBackground() {
  Workmanager().executeTask((_, _) async => true);
}

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
  testWidgets('owned Android calendar actions and task messenger regression', (
    tester,
  ) async {
    final guest = await Process.run('/system/bin/getprop', ['ro.kernel.qemu']);
    expect(Platform.isAndroid && guest.stdout.toString().trim() == '1', true);
    HttpOverrides.global = null;
    const endpoint = 'http://127.0.0.1:18811';
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
      await File('${support.path}/mykids-quality122-stage.json')
          .writeAsString(jsonEncode({'stage': name}));
      final ack = File('${support.path}/mykids-quality122-continue-$name');
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!await ack.exists()) {
        if (DateTime.now().isAfter(deadline)) fail('Capture timed out: $name');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await ack.delete();
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().isNotEmpty);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(target), alignment: .5);
      await tester.pump(const Duration(milliseconds: 200));
      await Scrollable.ensureVisible(tester.element(target), alignment: .5);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target.hitTestable());
      await tester.pumpAndSettle();
    }

    Future<void> login(String name) async {
      await repo.login(
        endpoint,
        'quality122-$name',
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
        Uri.parse('$endpoint/quality122/stats'),
        headers: {'X-MyKIDS-QA': 'quality122-loopback-only'},
      );
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    try {
      await Workmanager().initialize(submissionTestBackground);
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
        'Проверочное семейное сообщение120',
      );
      await tap(find.byTooltip('Отправить'));
      await until(
        () => find
            .text('Проверочное семейное сообщение120')
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
      final qr = File('${support.path}/quality122-synthetic-qr.png');
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

      var finalStats = await stats();
      final writes = finalStats['writes'] as List;
      expect(writes.every((row) => row['status'] == 200), true);
      final business = writes
          .where((row) => !row['path'].toString().endsWith('/receipt'))
          .toList();
      expect(business.length, 2);
      expect(business.first['path'], '/v1/invites');
      expect(business.last['body'], {
        'text': 'Проверочное семейное сообщение120',
      });
      expect(finalStats['attachments'], 0);
      expect(finalStats['ledger'], 0);
      expect(finalStats['invites'], 1);
      expect((finalStats['messages'] as List).length, 2);
      expect(finalStats['real_families'], false);

      // Real Android files, SQLite outbox and ordinary HTTP attachment/submission
      // endpoints; the gallery result itself uses this synthetic image only.
      final galleryData = await rootBundle.load(
        'assets/generated/calendar-task.png',
      );
      final gallery = File('${support.path}/quality122-gallery.png');
      await gallery.writeAsBytes(
        galleryData.buffer.asUint8List(
          galleryData.offsetInBytes,
          galleryData.lengthInBytes,
        ),
        flush: true,
      );
      final taskId = repo.rows('tasks').single['id'] as String;
      Future<List<File>> copies() async {
        final directory = Directory(
          '${support.path}/attachments/${repo.sessionTag}',
        );
        if (!await directory.exists()) return [];
        return (await directory.list().toList()).whereType<File>().toList();
      }

      Future<void> taskForm({
        Future<List<String>> Function(int)? picker,
        bool supplement = false,
      }) async {
        await mount();
        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  foregroundColor: ink,
                  title: const Text(
                    'Твои задания',
                    style: TextStyle(color: ink),
                  ),
                ),
                body: TaskScreen(
                  repository: repo,
                  focusTaskId: taskId,
                  selectPhotos: picker ?? (_) async => [gallery.path],
                  perform: (action) async {
                    await action();
                  },
                ),
              ),
            ),
          ),
        );
        await until(() => find.byType(TaskScreen).evaluate().isNotEmpty);
        await tester.scrollUntilVisible(
          find.text('Космический порядок'),
          120,
          scrollable: find
              .descendant(
                of: find.byType(TaskScreen),
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 40,
        );
        await tap(find.text('Космический порядок'));
        await tap(
          find.text(
            supplement
                ? 'Добавить фото к результату'
                : 'Готово — отправить на проверку',
          ),
        );
      }

      Future<void> pick() async {
        await tap(find.text('Добавить фото'));
        await until(
          () => find.text('Добавляем фотографии…').evaluate().isEmpty,
        );
        await until(
          () =>
              find.text('Фото 1').evaluate().isNotEmpty ||
              find.text('Фото 3').evaluate().isNotEmpty,
        );
      }

      for (final design in GameDesign.all) {
        gameDesign.value = design;
        await taskForm();
        await tester.enterText(find.byType(TextField), 'Результат для Лучика');
        await stage('task-style-${design.id}');
        await tap(find.text('Отмена'));
      }

      scale = 2;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
      ]);
      await tester.pumpAndSettle();
      await taskForm();
      await tap(find.text('Добавить фото'));
      await until(() => find.text('Фото 1').evaluate().isNotEmpty);
      await stage('task-short-landscape');
      await tap(find.text('Отмена'));
      await until(() => find.byType(AlertDialog).evaluate().isEmpty);
      expect(await copies(), isEmpty);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      scale = null;

      await taskForm();
      final cancelTask = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Отмена'))
          .onPressed!;
      await cover();
      cancelTask();
      await tester.pumpAndSettle();
      expect(find.text('Другой важный экран'), findsOneWidget);
      await stage('task-cover-preserved');
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await pick();
      final staleSubmit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Отправить на проверку'),
          )
          .onPressed!;
      repo.generation++;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      staleSubmit();
      await tester.pumpAndSettle();
      expect(find.text('Нужно открыть окно заново'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await stage('task-old-owner-blocked');
      await tap(find.text('Закрыть'));
      await until(() => find.byType(AlertDialog).evaluate().isEmpty);
      expect(await copies(), isEmpty);
      await login('child');

      final picker = Completer<List<String>>();
      await taskForm(picker: (_) => picker.future);
      await tap(find.text('Добавить фото'));
      await tap(find.text('Отмена'));
      picker.complete([gallery.path]);
      await tester.pumpAndSettle();
      expect(await copies(), isEmpty);
      expect((await stats())['attachments'], 0);
      await stage('task-picker-cancelled');

      wire.offline = true;
      repo.online = false;
      repo.notifyListeners();
      await taskForm(picker: (_) async => [gallery.path, gallery.path]);
      await tester.enterText(
        find.byType(TextField),
        'Две страницы для Лучика без связи',
      );
      await pick();
      expect(find.text('Всего фотографий: 2'), findsOneWidget);
      expect(await copies(), hasLength(2));
      await stage('task-photos-preview');
      final sendTask = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Отправить на проверку'),
          )
          .onPressed!;
      sendTask();
      sendTask();
      await until(() => find.text('Отличный шаг!').evaluate().isNotEmpty);
      expect(
        (await repo.pending()).where(
          (r) => r['path'] == '/v1/tasks/$taskId/submissions',
        ),
        hasLength(1),
      );
      expect((await stats())['attachments'], 0);
      await stage('task-offline-queued');
      await tap(find.text('Здорово!'));
      expect(await copies(), hasLength(2));

      wire.offline = false;
      repo.online = true;
      await repo.sync();
      await tester.pumpAndSettle();
      expect((await stats())['submissions'], hasLength(1));
      expect((await stats())['attachments'], 2);
      await stage('task-result-synced');
      await taskForm(supplement: true);
      await pick();
      await tap(find.text('Дослать фото'));
      await until(
        () => find.text('Фотографии добавлены').evaluate().isNotEmpty,
      );
      await stage('task-photo-supplemented');
      await tap(find.text('Здорово!'));
      finalStats = await stats();
      final commands = (finalStats['writes'] as List)
          .where((row) => !row['path'].toString().endsWith('/receipt'))
          .toList();
      expect(commands, hasLength(7));
      expect(commands.every((row) => row['status'] == 200), true);
      expect(
        commands.where((row) => row['path'] == '/v1/attachments'),
        hasLength(3),
      );
      expect(
        commands.where((row) => row['path'] == '/v1/tasks/$taskId/submissions'),
        hasLength(1),
      );
      expect(
        commands.where(
          (row) => row['path'] == '/v1/tasks/$taskId/submission-photos',
        ),
        hasLength(1),
      );
      expect(finalStats['ledger'], 0);
      expect(finalStats['attachments'], 3);
      expect(
        (finalStats['attachment_details'] as List).every(
          (row) => row['context_type'] == 'task' && row['mime'] == 'image/jpeg',
        ),
        true,
      );
      final submitted = (finalStats['submissions'] as List).single;
      expect(submitted['note'], 'Две страницы для Лучика без связи');
      expect(jsonDecode(submitted['attachment_ids'] as String), hasLength(3));
      expect(submitted['accepted'], 1);
      expect(await gallery.exists(), true);
      expect(await gallery.length(), galleryData.lengthInBytes);
      await gallery.delete();

      // The ordinary calendar, private SQLite queue and real isolated API.
      await login('parent');
      scale = 1.5;
      await mount();
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Семейный календарь')),
              body: ListenableBuilder(
                listenable: repo,
                builder: (_, _) => CalendarScreen(
                  repository: repo,
                  initialDay: DateTime.utc(2026, 10, 12, 12),
                  perform: (action) async {
                    await action();
                  },
                  openTasks: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tap(find.text('Добавить событие'));
      await tester.enterText(
        find.byKey(const ValueKey('event-title')),
        'Маршрут Лучика',
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-note')),
        'Личное примечание экспедиции',
      );
      await tap(find.widgetWithText(OutlinedButton, 'Дата: Пн, 12.10.2026'));
      final dates = MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)),
      );
      await tap(find.byTooltip(dates.inputDateModeButtonLabel));
      await tester.enterText(
        find.descendant(
          of: find.byType(InputDatePickerFormField),
          matching: find.byType(TextFormField),
        ),
        dates.formatCompactDate(DateTime(2026, 10, 12)),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final dateOK = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, dates.okButtonLabel),
          )
          .onPressed!;
      await cover();
      dateOK();
      await tester.pumpAndSettle();
      expect(find.text('Другой важный экран'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await stage('calendar-date-picker');
      await tap(find.widgetWithText(TextButton, dates.okButtonLabel));
      await stage('calendar-new-event');
      final firstSave = tester
          .widget<FilledButton>(find.byKey(const ValueKey('event-save')))
          .onPressed!;
      firstSave();
      firstSave();
      await until(() => find.byType(CalendarEditor).evaluate().isEmpty);
      final schedule = repo.rows('schedules').single;
      final scheduleId = schedule['id'];
      expect(schedule['date'], '2026-10-12');
      expect(schedule['title'], 'Маршрут Лучика');
      await tap(find.text('Маршрут Лучика'));
      await tap(find.widgetWithText(FilledButton, 'Изменить событие'));
      await tester.enterText(
        find.byKey(const ValueKey('event-title')),
        'Маршрут Лучика обновлён',
      );
      await tap(find.byKey(const ValueKey('event-start')));
      await stage('calendar-time-picker');
      await tester.enterText(find.byKey(const ValueKey('time-minute')), '30');
      await tap(find.widgetWithText(TextButton, 'Готово'));
      await tap(find.byKey(const ValueKey('event-save')));
      await until(() => find.byType(CalendarEditor).evaluate().isEmpty);
      // The real API persists time.isoformat(), including zero seconds.
      expect(repo.rows('schedules').single['start'], '09:30:00');
      expect(repo.rows('schedules').single['title'], 'Маршрут Лучика обновлён');
      await tap(find.text('Маршрут Лучика обновлён'));
      await tap(find.widgetWithText(FilledButton, 'Изменить событие'));
      wire.offline = true;
      repo.online = false;
      repo.notifyListeners();
      await tester.enterText(
        find.byKey(const ValueKey('event-note')),
        'Уточнение маршрута без связи',
      );
      await tap(find.byKey(const ValueKey('event-save')));
      await until(() => find.byType(CalendarEditor).evaluate().isEmpty);
      expect(
        (await repo.pending()).where(
          (r) => r['path'] == '/v1/schedules/$scheduleId',
        ),
        hasLength(1),
      );
      await stage('calendar-offline-queued');
      wire.offline = false;
      repo.online = true;
      await repo.sync();
      await tester.pumpAndSettle();
      expect(await repo.pending(), isEmpty);
      expect(
        repo.rows('schedules').single['note'],
        'Уточнение маршрута без связи',
      );
      await stage('calendar-event-synced');
      await tap(find.text('Маршрут Лучика обновлён'));
      await tap(find.widgetWithText(TextButton, 'Удалить событие'));
      final oldDelete = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить'),
          )
          .onPressed!;
      final oldBack = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Назад'))
          .onPressed!;
      await cover();
      oldDelete();
      oldBack();
      await tester.pumpAndSettle();
      expect(find.text('Другой важный экран'), findsOneWidget);
      expect(repo.rows('schedules'), hasLength(1));
      await stage('calendar-cover-preserved');
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      repo.snapshot!['user']['role'] = 'child';
      repo.notifyListeners();
      repo.snapshot!['user']['role'] = 'parent';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      oldDelete();
      await tester.pumpAndSettle();
      expect(find.text('Нужно открыть окно заново'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Маршрут Лучика обновлён'),
        ),
        findsNothing,
      );
      expect(repo.rows('schedules'), hasLength(1));
      await stage('calendar-old-owner-blocked');
      await tap(find.widgetWithText(TextButton, 'Закрыть'));
      await tap(find.text('Маршрут Лучика обновлён'));
      await tap(find.widgetWithText(TextButton, 'Удалить событие'));
      await stage('calendar-delete-confirmation');
      final delete = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить'),
          )
          .onPressed!;
      delete();
      delete();
      await until(() => repo.rows('schedules').isEmpty);
      finalStats = await stats();
      final calendarWrites = (finalStats['writes'] as List)
          .where((r) => r['path'].toString().startsWith('/v1/schedules'))
          .toList();
      expect(calendarWrites.map((r) => r['method']).toList(), [
        'POST',
        'PUT',
        'PUT',
        'DELETE',
      ]);
      expect(calendarWrites.every((r) => r['status'] == 200), true);
      expect(
        (finalStats['writes'] as List).where(
          (r) => !r['path'].toString().endsWith('/receipt'),
        ),
        hasLength(11),
      );
      expect(finalStats['ledger'], 0);
      expect(tester.takeException(), isNull);
      await File('${support.path}/mykids-quality122-before-penalty-stats.json')
          .writeAsString(jsonEncode(finalStats));

      final seeded = await control.post(
        Uri.parse('$endpoint/quality122/penalty-window'),
        headers: {'X-MyKIDS-QA': 'quality122-loopback-only'},
      );
      expect(seeded.statusCode, 200);
      final probe = jsonDecode(seeded.body) as Map<String, dynamic>;
      expect(probe['real_families'], false);
      final liveTask = probe['live_task'] as String;
      final olderTask = probe['older_task'] as String;
      final olderPenalty = probe['older_penalty'] as String;
      await repo.sync();
      await tester.pumpAndSettle();
      final seededStats = await stats();
      expect(seededStats['ledger'], 0);
      await File('${support.path}/mykids-quality122-seeded-penalty-stats.json')
          .writeAsString(jsonEncode(seededStats));
      await mount();
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Семейные монеты')),
              body: ListenableBuilder(
                listenable: repo,
                builder: (_, _) => MoneyScreen(
                  repository: repo,
                  perform: (operation) async {
                    await operation();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final older = repo.rows('tasks').firstWhere((r) => r['id'] == olderTask);
      final oldTime = taskCalendarTimeText(repo.snapshot, older)!;
      final card = find.byKey(ValueKey('penalty-$olderPenalty'));
      await until(() => card.evaluate().isNotEmpty);
      await Scrollable.ensureVisible(tester.element(card));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: card, matching: find.text(oldTime)),
        findsOneWidget,
      );
      await stage('penalty-occurrence-list');
      await tap(
        find.descendant(
          of: card,
          matching: find.widgetWithText(FilledButton, 'Применить'),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(oldTime),
        ),
        findsOneWidget,
      );
      await stage('penalty-occurrence-consent');
      await tap(find.widgetWithText(TextButton, 'Отмена'));
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Сегодня')),
              body: ListenableBuilder(
                listenable: repo,
                builder: (_, _) => TodayScreen(
                  repository: repo,
                  openPage: (_) => fail('Open the exact review'),
                  onReviewTask: (id) =>
                      openTaskReview(context, repo, (operation) async {
                        await operation();
                      }, id),
                ),
              ),
            ),
          ),
        ),
      );
      await tap(find.byKey(ValueKey('today-review-$liveTask')));
      final live = repo.rows('tasks').firstWhere((r) => r['id'] == liveTask);
      expect(
        DateTime.parse(live['planned_end'] as String).isBefore(DateTime.now()),
        true,
      );
      expect(
        DateTime.parse(live['due_at'] as String).isAfter(DateTime.now()),
        true,
      );
      final oldApprove = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить выполнение'),
          )
          .onPressed!;
      final failButton = find.byKey(ValueKey('task-not-completed-$liveTask'));
      await Scrollable.ensureVisible(tester.element(failButton));
      await tester.pumpAndSettle();
      expect(find.text('Скрыть подробности'), findsNothing);
      await stage('task-penalty-before-report-deadline');
      await tap(failButton);
      expect(
        find.textContaining(taskCalendarTimeText(repo.snapshot, live)!),
        findsOneWidget,
      );
      await stage('task-penalty-confirmation');
      expect(find.text('Штраф: 500 монет'), findsOneWidget);
      final charge = find.widgetWithText(FilledButton, 'Списать 500 монет');
      expect(charge.hitTestable(), findsOneWidget);
      await tap(charge);
      await until(
        () =>
            repo
                .rows('tasks')
                .firstWhere((r) => r['id'] == liveTask)['status'] ==
            'not_completed',
      );
      expect(find.text('Подтвердить выполнение'), findsNothing);
      await stage('task-penalty-applied');
      oldApprove();
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('today-review-$liveTask')), findsNothing);
      expect(find.text('Результатов на проверке: 1'), findsOneWidget);
      await stage('today-penalty-closed-occurrence');
      finalStats = await stats();
      expect(finalStats['ledger'], 1);
      expect((finalStats['ledger_details'] as List).single, {
        'source_id': liveTask,
        'requested': -500,
        'actual': -500,
      });
      final penaltyBusiness = (finalStats['writes'] as List)
          .where((r) => !r['path'].toString().endsWith('/receipt'))
          .toList();
      expect(penaltyBusiness, hasLength(12));
      expect(penaltyBusiness.last['path'], '/v1/tasks/$liveTask/actions');
      expect(penaltyBusiness.last['body'], {
        'action': 'not_completed',
        'task_version': 1,
      });
      expect(penaltyBusiness.every((r) => r['status'] == 200), true);
      expect(
        (finalStats['penalty_details'] as List).firstWhere(
          (r) => r['id'] == olderPenalty,
        )['status'],
        'pending',
      );
      expect(
        (finalStats['penalty_details'] as List).singleWhere(
          (r) => r['source_id'] == liveTask,
        )['status'],
        'applied',
      );
      expect(tester.takeException(), isNull);
      await File('${support.path}/mykids-quality122-server-stats.json')
          .writeAsString(jsonEncode(finalStats));
      await File('${support.path}/mykids-quality122-penalty-proof.json')
          .writeAsString(jsonEncode(probe));
      await File('${support.path}/mykids-quality122-proof.json').writeAsString(
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
          'no_unintended_voice_uploads_or_money_changes': true,
          'task_five_styles_and_short_landscape': true,
          'task_old_owner_and_cover_blocked': true,
          'task_cancelled_photos_removed_gallery_preserved': true,
          'task_offline_queue_once_and_real_upload': true,
          'task_photo_supplement_delivered': true,
          'calendar_create_edit_and_delete_real_api': true,
          'calendar_offline_queue_once_and_sync': true,
          'calendar_old_owner_and_cover_blocked': true,
          'explicit_penalty_before_reporting_deadline': true,
          'money_penalty_occurrence_and_consent_match': true,
          'penalty_closes_only_its_occurrence_and_blocks_old_approval': true,
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
