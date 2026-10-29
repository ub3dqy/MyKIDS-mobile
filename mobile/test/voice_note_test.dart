import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/voice_note.dart';
import 'package:record/record.dart';

import 'support/owned_temp.dart';

class Capture implements VoiceCapture {
  final events = StreamController<RecordState>.broadcast();
  Completer<bool>? permission;
  Completer<void>? starting, stopping;
  String? path;
  bool running = false, paused = false, granted = true, empty = false;
  bool failCancel = false, failClose = false, failStop = false;
  int starts = 0, stops = 0, closes = 0;
  @override
  Future<bool> hasPermission() async => permission?.future ?? granted;
  @override
  Future<void> start(String path) async {
    starts++;
    this.path = path;
    if (starting != null) await starting!.future;
    await File(path).writeAsBytes(List.filled(empty ? 44 : 3244, 0));
    running = true;
    events.add(RecordState.record);
  }

  @override
  Future<String?> stop() async {
    stops++;
    if (stopping != null) await stopping!.future;
    if (failStop) throw StateError('Synthetic native stop failure');
    running = false;
    events.add(RecordState.stop);
    return path;
  }

  @override
  Future<void> cancel() async {
    running = false;
    if (path != null && File(path!).existsSync()) await File(path!).delete();
    if (failCancel) throw StateError('Synthetic cancel failure');
  }

  @override
  Future<void> close() async {
    closes++;
    running = false;
    if (failClose) throw StateError('Synthetic close failure');
  }

  @override
  Future<bool> isRecording() async => running;
  @override
  Future<bool> isPaused() async => paused;
  @override
  Stream<RecordState> get states => events.stream;
}

void main() {
  late Directory folder;
  late Capture capture;
  late VoiceNote voice;
  late bool owner, active;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('mykids-voice-state-');
    capture = Capture();
    owner = active = true;
    voice = VoiceNote(
      capture: capture,
      directory: () async => folder,
      isOwner: () => owner,
      isActive: () => active,
    );
  });
  tearDown(() async {
    try {
      await voice.close();
    } catch (_) {
      /* Explicitly tested below. */
    }
    voice.dispose();
    await capture.events.close();
    await deleteOwnedTestTemp(folder);
  });
  Future<void> ready() async {
    expect(await voice.start(), true);
    await voice.finish();
    expect(voice.canSend, true);
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), true);
  }

  test(
    'stopping keeps a private draft until an explicit successful send',
    () async {
      await ready();
      final path = voice.draft!;
      expect(File(path).existsSync(), true);
      var sends = 0;
      await voice.send((p) async {
        expect(p, path);
        expect(File(p).existsSync(), true);
        sends++;
      });
      expect(sends, 1);
      expect(voice.phase, VoiceNotePhase.idle);
      expect(File(path).existsSync(), false);
    },
  );
  test('failed upload keeps the same bytes and can be retried once', () async {
    await ready();
    final path = voice.draft!;
    final bytes = await File(path).readAsBytes();
    await expectLater(
      voice.send((_) async => throw const SocketException('offline')),
      throwsA(isA<SocketException>()),
    );
    expect(voice.draft, path);
    expect(await File(path).readAsBytes(), bytes);
    var sends = 0;
    await voice.send((_) async {
      sends++;
    });
    expect(sends, 1);
    expect(File(path).existsSync(), false);
  });
  test('double send cannot upload a draft twice', () async {
    await ready();
    final accepted = Completer<void>();
    var sends = 0;
    final first = voice.send((_) async {
      sends++;
      await accepted.future;
    });
    await voice.send((_) async {
      sends++;
    });
    expect(sends, 1);
    accepted.complete();
    await first;
  });
  test('background finishes into a draft and never sends', () async {
    await voice.start();
    active = false;
    await voice.suspend();
    expect(capture.running, false);
    expect(voice.phase, VoiceNotePhase.ready);
    expect(voice.canSend, false);
    var sends = 0;
    await voice.send((_) async {
      sends++;
    });
    expect(sends, 0);
    active = true;
    expect(voice.canSend, true);
  });
  test('duration limit finishes locally with no delivery callback', () async {
    await voice.close();
    voice.dispose();
    voice = VoiceNote(
      capture: capture,
      directory: () async => folder,
      isOwner: () => owner,
      isActive: () => active,
      limit: const Duration(milliseconds: 25),
    );
    await voice.start();
    await waitFor(() => voice.phase == VoiceNotePhase.ready);
    expect(capture.running, false);
    expect(voice.draft, isNotNull);
  });
  test('cancel removes only files owned by the current recording', () async {
    final other = File('${folder.path}/another-recording.wav');
    await other.writeAsString('another screen owns this');
    await ready();
    final path = voice.draft!;
    await voice.cancel();
    expect(File(path).existsSync(), false);
    expect(other.existsSync(), true);
    expect(voice.hasUnsent, false);
  });
  test(
    'a late microphone permission cannot start after cancellation',
    () async {
      capture.permission = Completer<bool>();
      final old = voice.start();
      await voice.cancel();
      capture.permission!.complete(true);
      expect(await old, false);
      expect(capture.starts, 0);
      expect(folder.listSync(), isEmpty);
    },
  );
  test('permission denial leaves the controls available for retry', () async {
    capture.granted = false;
    await expectLater(voice.start(), throwsA(isA<Exception>()));
    expect(voice.phase, VoiceNotePhase.idle);
    capture.granted = true;
    expect(await voice.start(), true);
  });
  test(
    'permission granted before focus returns waits for the recording screen',
    () async {
      capture.permission = Completer<bool>();
      final starting = voice.start();
      active = false;
      capture.permission!.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(capture.starts, 0);
      active = true;
      voice.resume();
      expect(await starting, true);
    },
  );
  test(
    'leaving during permission focus recovery cannot start on a later resume',
    () async {
      capture.permission = Completer<bool>();
      final starting = voice.start();
      active = false;
      capture.permission!.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await voice.suspend(cancelPermission: true);
      active = true;
      voice.resume();
      expect(await starting, false);
      expect(capture.starts, 0);
    },
  );
  test(
    'cancel during slow native start cannot cancel the next recording',
    () async {
      capture.starting = Completer<void>();
      final old = voice.start();
      await waitFor(() => capture.starts == 1);
      final oldPath = capture.path!;
      final cancelled = voice.cancel();
      final next = voice.start();
      capture.starting!.complete();
      await cancelled;
      expect(await old, false);
      expect(await next, true);
      expect(File(oldPath).existsSync(), false);
      expect(capture.running, true);
      expect(capture.path, isNot(oldPath));
    },
  );
  test(
    'slow native stop after cancel cannot restore a discarded draft',
    () async {
      await voice.start();
      final path = capture.path!;
      capture.stopping = Completer<void>();
      final stopping = voice.finish();
      await waitFor(() => capture.stops == 1);
      final cancelled = voice.cancel();
      capture.stopping!.complete();
      await stopping;
      await cancelled;
      expect(voice.phase, VoiceNotePhase.idle);
      expect(voice.draft, isNull);
      expect(File(path).existsSync(), false);
    },
  );
  test(
    'revoking the screen owner during native start stops and deletes',
    () async {
      capture.starting = Completer<void>();
      final starting = voice.start();
      await waitFor(() => capture.starts == 1);
      owner = false;
      capture.starting!.complete();
      expect(await starting, false);
      expect(capture.running, false);
      expect(folder.listSync(), isEmpty);
    },
  );
  test('stale native stop event cannot interrupt a new recording', () async {
    await voice.start();
    await voice.cancel();
    await voice.start();
    capture.events.add(RecordState.stop);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(voice.recording, true);
    expect(capture.running, true);
  });
  test('native pause ends the recording with a local draft', () async {
    await voice.start();
    capture.paused = true;
    capture.events.add(RecordState.pause);
    await waitFor(() => voice.phase == VoiceNotePhase.ready);
    expect(capture.running, false);
  });
  test('an empty native file is discarded and can be recorded again', () async {
    capture.empty = true;
    await voice.start();
    await expectLater(voice.finish(), throwsA(isA<Exception>()));
    expect(folder.listSync(), isEmpty);
    expect(voice.phase, VoiceNotePhase.idle);
    capture.empty = false;
    await ready();
  });
  test(
    'leaving during an upload keeps the file until transport finishes',
    () async {
      await ready();
      final path = voice.draft!;
      final accepted = Completer<void>();
      final sending = voice.send((p) async {
        await accepted.future;
        expect(File(p).existsSync(), true);
      });
      final closing = voice.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(File(path).existsSync(), true);
      accepted.complete();
      await sending;
      await closing;
      expect(File(path).existsSync(), false);
    },
  );
  test(
    'failed upload after owner changes deletes instead of restoring a draft',
    () async {
      await ready();
      final path = voice.draft!;
      final response = Completer<void>();
      final sending = voice.send((_) => response.future);
      final assertion = expectLater(sending, throwsA(isA<StateError>()));
      owner = false;
      final cancelled = voice.cancel();
      await cancelled;
      expect(File(path).existsSync(), true);
      response.completeError(StateError('Synthetic failure'));
      await assertion;
      expect(File(path).existsSync(), false);
      expect(voice.draft, isNull);
    },
  );
  test(
    'native cleanup errors do not prevent file deletion or resource close',
    () async {
      await ready();
      final path = voice.draft!;
      capture.failCancel = capture.failClose = true;
      await expectLater(voice.close(), throwsA(isA<StateError>()));
      expect(capture.closes, 1);
      expect(File(path).existsSync(), false);
    },
  );
  test(
    'native stop failure still releases the microphone and removes the file',
    () async {
      await voice.start();
      final path = capture.path!;
      capture.failStop = true;
      await expectLater(voice.finish(), throwsA(isA<StateError>()));
      expect(capture.running, false);
      expect(File(path).existsSync(), false);
      expect(voice.phase, VoiceNotePhase.idle);
      capture.failStop = false;
      await ready();
    },
  );
  test(
    'failed stop and cancel close the device before allowing another capture',
    () async {
      await voice.start();
      capture.failStop = capture.failCancel = true;
      await expectLater(voice.finish(), throwsA(isA<StateError>()));
      expect(capture.closes, 1);
      expect(capture.running, false);
      await expectLater(voice.start(), throwsA(isA<Exception>()));
      expect(capture.starts, 1);
    },
  );
}
