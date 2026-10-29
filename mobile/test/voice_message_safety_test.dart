import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:record/record.dart';

import 'support/messenger_fixture.dart';
import 'support/owned_temp.dart';

class VoicePlayer implements AudioPlayer {
  int plays = 0, stops = 0;
  Completer<Duration?>? loading;
  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async => loading?.future ?? Duration.zero;
  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Stream<PlayerState> get playerStateStream =>
      Stream.value(PlayerState(false, ProcessingState.idle));
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class VoicePlatform extends RecordPlatform {
  final states = StreamController<RecordState>.broadcast();
  String? path;
  bool capturing = false;
  int starts = 0, stops = 0, cancels = 0;
  Completer<bool>? permission;

  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      permission == null ? true : permission!.future;
  @override
  Stream<RecordState> onStateChanged(String recorderId) => states.stream;
  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig)? handler,
  ) {}
  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    starts++;
    this.path = path;
    final bytes = Uint8List(44 + 3200);
    bytes.setRange(0, 4, 'RIFF'.codeUnits);
    bytes.setRange(8, 12, 'WAVE'.codeUnits);
    File(path).parent.createSync(recursive: true);
    File(path).writeAsBytesSync(bytes);
    capturing = true;
    states.add(RecordState.record);
  }

  @override
  Future<String?> stop(String recorderId) async {
    stops++;
    capturing = false;
    states.add(RecordState.stop);
    return path;
  }

  @override
  Future<void> cancel(String recorderId) async {
    cancels++;
    capturing = false;
    if (path != null && File(path!).existsSync()) File(path!).deleteSync();
  }

  @override
  Future<void> dispose(String recorderId) async {
    capturing = false;
  }

  @override
  Future<bool> isRecording(String recorderId) async => capturing;
  @override
  Future<bool> isPaused(String recorderId) async => false;
  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: 0, max: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class VoiceFixture extends MessengerFixture {
  int uploads = 0, voiceMessages = 0;
  bool rejectUpload = false;
  Completer<void>? uploadGate;
  late Directory folder;
  @override
  Future<File> attachment(String id) async {
    final file = File('${folder.path}/received.wav');
    await file.writeAsBytes([
      ...'RIFF'.codeUnits,
      0,
      0,
      0,
      0,
      ...'WAVE'.codeUnits,
      ...List.filled(100, 0),
    ]);
    return file;
  }

  @override
  Future<Map<String, dynamic>> upload(
    String path,
    String contextType,
    String contextId,
  ) async {
    uploads++;
    await uploadGate?.future;
    expect(File(path).existsSync(), true);
    if (rejectUpload) throw ApiFailure(503, 'Не удалось отправить запись');
    return {'id': 'synthetic-voice'};
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    if (body['attachment_id'] != null) {
      voiceMessages++;
      return {'id': 'synthetic-message'};
    }
    return super.mutate(
      path,
      body,
      method: method,
      offlineSubmission: offlineSubmission,
      files: files,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late VoicePlatform native;
  late RecordPlatform original;
  late VoiceFixture repo;
  late VoicePlayer player;
  late GlobalKey<NavigatorState> navigator;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('mykids-voice-ui-');
    original = RecordPlatform.instance;
    native = VoicePlatform();
    RecordPlatform.instance = native;
    repo = VoiceFixture()..folder = folder;
    player = VoicePlayer();
    navigator = GlobalKey<NavigatorState>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => folder.path,
        );
  });
  tearDown(() async {
    RecordPlatform.instance = original;
    await native.states.close();
    repo.client.close();
    repo.dispose();
    await deleteOwnedTestTemp(folder);
  });
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
  }

  Future<void> open(
    WidgetTester tester, {
    bool landing = false,
    bool largeText = false,
  }) async {
    final chat = ChatScreen(
      repository: repo,
      audioPlayer: player,
      room: repo.rows('rooms').firstWhere((r) => r['kind'] == 'private'),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: largeText
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              )
            : null,
        home: landing ? const Scaffold(body: Text('Начало')) : chat,
      ),
    );
    await tester.pumpAndSettle();
    if (landing) {
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => chat),
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Голосовое'));
    await settleIo(tester);
    expect(
      native.capturing,
      true,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' / '),
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settleIo(tester);
  }

  testWidgets('voice recording has an explicit cancel action', (tester) async {
    await open(tester);
    try {
      await start(tester);
      expect(find.byTooltip('Отменить запись'), findsOneWidget);
    } finally {
      await close(tester);
    }
  });
  testWidgets('backgrounding stops capture without sending a voice message', (
    tester,
  ) async {
    await open(tester);
    try {
      await start(tester);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await settleIo(tester);
      expect(native.capturing, false);
      expect(repo.uploads, 0);
      await tester.pump(const Duration(seconds: 116));
      await settleIo(tester);
      expect(repo.voiceMessages, 0);
    } finally {
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await close(tester);
    }
  });
  testWidgets(
    'permission completion cannot start recording for a changed account',
    (tester) async {
      native.permission = Completer<bool>();
      await open(tester);
      try {
        await tester.tap(find.byTooltip('Голосовое'));
        await tester.pump();
        repo.token = 'synthetic-new-account';
        repo.generation++;
        repo.snapshot!['user'] = {'id': 'other', 'role': 'parent'};
        repo.notifyListeners();
        native.permission!.complete(true);
        await settleIo(tester);
        expect(native.starts, 0);
        expect(repo.uploads, 0);
      } finally {
        await close(tester);
      }
    },
  );
  testWidgets('leaving a recording removes its owned temporary file', (
    tester,
  ) async {
    await open(tester);
    await start(tester);
    final path = native.path!;
    await close(tester);
    expect(File(path).existsSync(), false);
    expect(repo.uploads, 0);
  });
  testWidgets('stop, preview and cancel do not send a message', (tester) async {
    await open(tester);
    try {
      await start(tester);
      await tester.tap(find.byTooltip('Остановить запись'));
      await settleIo(tester);
      final path = native.path!;
      expect(native.capturing, false);
      expect(find.text('Запись готова'), findsOneWidget);
      await tester.tap(find.byTooltip('Прослушать запись'));
      await settleIo(tester);
      expect(player.plays, 1);
      await tester.tap(find.byTooltip('Отменить запись'));
      await settleIo(tester);
      expect(File(path).existsSync(), false);
      expect(repo.uploads, 0);
      expect(find.byTooltip('Голосовое'), findsOneWidget);
    } finally {
      await close(tester);
    }
  });
  testWidgets('failed voice sending keeps a retryable draft and sends once', (
    tester,
  ) async {
    await open(tester);
    try {
      await start(tester);
      await tester.tap(find.byTooltip('Остановить запись'));
      await settleIo(tester);
      final path = native.path!;
      repo.rejectUpload = true;
      await tester.tap(find.byTooltip('Отправить запись'));
      await settleIo(tester);
      expect(find.text('Не удалось отправить запись'), findsOneWidget);
      expect(find.byTooltip('Прослушать запись'), findsOneWidget);
      expect(File(path).existsSync(), true);
      repo.rejectUpload = false;
      repo.uploadGate = Completer<void>();
      await tester.tap(find.byTooltip('Отправить запись'));
      await tester.pump();
      await tester.tap(find.byTooltip('Отправить запись'));
      await settleIo(tester);
      expect(repo.uploads, 2);
      repo.uploadGate!.complete();
      await settleIo(tester);
      expect(repo.voiceMessages, 1);
      expect(File(path).existsSync(), false);
    } finally {
      await close(tester);
    }
  });
  testWidgets('opening another screen stops recording into a draft', (
    tester,
  ) async {
    await open(tester);
    try {
      await start(tester);
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Другое окно')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await settleIo(tester);
      expect(native.capturing, false);
      expect(repo.uploads, 0);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Запись готова'), findsOneWidget);
    } finally {
      await close(tester);
    }
  });
  testWidgets('Back offers to keep or delete an unsent voice draft', (
    tester,
  ) async {
    await open(tester, landing: true);
    try {
      await start(tester);
      final path = native.path!;
      await navigator.currentState!.maybePop();
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(native.capturing, false);
      expect(find.text('Удалить голосовую запись?'), findsOneWidget);
      await tester.tap(find.text('Остаться'));
      await tester.pumpAndSettle();
      expect(find.text('Запись готова'), findsOneWidget);
      expect(File(path).existsSync(), true);
      await navigator.currentState!.maybePop();
      await settleIo(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить и выйти'));
      await tester.pumpAndSettle();
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.text('Начало'), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(File(path).existsSync(), false);
      expect(repo.uploads, 0);
    } finally {
      await close(tester);
    }
  });
  testWidgets('time limit keeps the recording local for explicit delivery', (
    tester,
  ) async {
    await open(tester);
    try {
      await start(tester);
      await tester.pump(const Duration(seconds: 116));
      await settleIo(tester);
      expect(native.capturing, false);
      expect(find.text('Запись готова'), findsOneWidget);
      expect(repo.uploads, 0);
      expect(File(native.path!).existsSync(), true);
    } finally {
      await close(tester);
    }
  });
  testWidgets(
    'changing the account stops capture and erases its private file',
    (tester) async {
      await open(tester);
      try {
        await start(tester);
        final path = native.path!;
        repo.token = 'synthetic-changed';
        repo.generation++;
        repo.notifyListeners();
        await settleIo(tester);
        expect(native.capturing, false);
        expect(File(path).existsSync(), false);
        expect(repo.uploads, 0);
      } finally {
        await close(tester);
      }
    },
  );
  for (final background in [false, true]) {
    testWidgets(
      'late playback preparation cannot start after ${background ? 'backgrounding' : 'covering the chat'}',
      (tester) async {
        player.loading = Completer<Duration?>();
        await open(tester);
        try {
          await start(tester);
          await tester.tap(find.byTooltip('Остановить запись'));
          await settleIo(tester);
          await tester.tap(find.byTooltip('Прослушать запись'));
          await tester.pump();
          if (background) {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
          } else {
            unawaited(
              navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Другое окно')),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }
          player.loading!.complete(Duration.zero);
          await settleIo(tester);
          expect(player.plays, 0);
        } finally {
        if (background) {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
        }
          await close(tester);
        }
      },
    );
  }
  testWidgets('recording controls fit a 320px screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, largeText: true);
    try {
      await start(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Остановить запись'));
      await settleIo(tester);
      expect(tester.takeException(), isNull);
      for (final label in [
        'Прослушать запись',
        'Отменить запись',
        'Отправить запись',
      ]) {
        final rect = tester.getRect(find.byTooltip(label));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.size.shortestSide, greaterThanOrEqualTo(48));
      }
    } finally {
      await close(tester);
    }
  });
  testWidgets('leaving during upload keeps the file until delivery completes', (
    tester,
  ) async {
    repo.uploadGate = Completer<void>();
    await open(tester);
    await start(tester);
    await tester.tap(find.byTooltip('Остановить запись'));
    await settleIo(tester);
    final path = native.path!;
    await tester.tap(find.byTooltip('Отправить запись'));
    await settleIo(tester);
    await close(tester);
    expect(File(path).existsSync(), true);
    repo.uploadGate!.complete();
    await settleIo(tester);
    expect(repo.voiceMessages, 1);
    expect(File(path).existsSync(), false);
  });
}
