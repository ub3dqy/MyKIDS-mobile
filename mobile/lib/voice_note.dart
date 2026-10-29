import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'repository.dart';

enum VoiceNotePhase {
  idle,
  permission,
  starting,
  recording,
  stopping,
  ready,
  sending,
  closed,
}

abstract interface class VoiceCapture {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<String?> stop();
  Future<void> cancel();
  Future<bool> isRecording();
  Future<bool> isPaused();
  Stream<RecordState> get states;
  Future<void> close();
}

class DeviceVoiceCapture implements VoiceCapture {
  final recorder = AudioRecorder();
  @override
  Future<bool> hasPermission() => recorder.hasPermission();
  @override
  Future<void> start(String path) => recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    ),
    path: path,
  );
  @override
  Future<String?> stop() => recorder.stop();
  @override
  Future<void> cancel() => recorder.cancel();
  @override
  Future<bool> isRecording() => recorder.isRecording();
  @override
  Future<bool> isPaused() => recorder.isPaused();
  @override
  Stream<RecordState> get states => recorder.onStateChanged();
  @override
  Future<void> close() => recorder.dispose();
}

/// A local recording belongs to one screen and authenticated reader. Native
/// operations remain ordered even when permission/start/stop completes late.
class VoiceNote extends ChangeNotifier {
  final bool Function() isOwner, isActive;
  final VoiceCapture capture;
  final Future<Directory> Function() directory;
  final Duration limit;
  VoiceNote({
    required this.isOwner,
    required this.isActive,
    VoiceCapture? capture,
    Future<Directory> Function()? directory,
    this.limit = const Duration(seconds: 115),
  }) : capture = capture ?? DeviceVoiceCapture(),
       directory = directory ?? _directory {
    if (limit <= Duration.zero || limit > const Duration(seconds: 115)) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Recording limit must be within 115 seconds',
      );
    }
  }
  static Future<Directory> _directory() async => Directory(
    p.join((await getTemporaryDirectory()).path, 'mykids-voice-notes'),
  );
  VoiceNotePhase phase = VoiceNotePhase.idle;
  String? error;
  String? _captured, _draft;
  String? get draft => phase == VoiceNotePhase.ready ? _draft : null;
  bool get recording => phase == VoiceNotePhase.recording;
  bool get hasUnsent =>
      phase != VoiceNotePhase.sending && (_captured != null || _draft != null);
  bool get hasPanel =>
      phase != VoiceNotePhase.idle && phase != VoiceNotePhase.closed;
  bool get canFinish => phase == VoiceNotePhase.recording;
  bool get canSend => phase == VoiceNotePhase.ready && _active;
  bool get _owner => !_closed && isOwner();
  bool get _active => _owner && isActive();
  bool _closed = false, _unavailable = false;
  int _epoch = 0;
  Timer? _timer;
  StreamSubscription<RecordState>? _states;
  Future<void> _tail = Future<void>.value();
  Future<void>? _finishing, _closing;
  Completer<void>? _permissionResume;
  final _owned = <String>{}, _leased = <String>{};
  final _sends = <Future<void>>{};
  bool _current(int epoch) => epoch == _epoch && _owner;

  void _changed(VoiceNotePhase next) {
    if (_closed) return;
    phase = next;
    notifyListeners();
  }

  Future<T> _native<T>(Future<T> Function() action) {
    final result = _tail.then<T>((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _delete(String path) async {
    if (!_owned.contains(path) || _leased.contains(path)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
    _owned.remove(path);
  }

  Future<void> _abortNative() async {
    try {
      await capture.cancel();
    } catch (_) {
      _unavailable = true;
      await capture.close();
      rethrow;
    }
  }

  Future<bool> start() async {
    if (phase != VoiceNotePhase.idle || !_active) return false;
    if (_unavailable) {
      throw ApiFailure(503, 'Микрофон недоступен. Откройте чат заново');
    }
    final epoch = ++_epoch;
    error = null;
    _changed(VoiceNotePhase.permission);
    try {
      final granted = await capture.hasPermission();
      if (!_current(epoch)) return false;
      if (!granted) {
        throw ApiFailure(403, 'Разрешите микрофон для голосового сообщения');
      }
      // Android can deliver permission before restoring the activity's focus.
      // Hidden routes/background/disposal cancel this wait instead of starting
      // the microphone later without an active recording screen.
      if (!_active) {
        final resumed = _permissionResume = Completer<void>();
        await resumed.future;
        if (identical(_permissionResume, resumed)) _permissionResume = null;
      }
      if (!_current(epoch) || !_active) return false;
      final folder = await directory();
      if (!_current(epoch) || !_active) return false;
      await folder.create(recursive: true);
      if (!_current(epoch) || !_active) return false;
      final path = p.join(folder.path, '${const Uuid().v4()}.wav');
      _owned.add(path);
      _captured = path;
      _states ??= capture.states.listen(
        _stateChanged,
        onError: (Object _) => unawaited(_automaticFinish()),
      );
      _changed(VoiceNotePhase.starting);
      await _native(() async {
        if (!_current(epoch) || !_active) {
          await _delete(path);
          return;
        }
        try {
          await capture.start(path);
          if (!_current(epoch) || !_active) {
            await _abortNative();
            await _delete(path);
            return;
          }
          _changed(VoiceNotePhase.recording);
          _timer = Timer(limit, () => unawaited(_automaticFinish()));
        } catch (_) {
          try {
            await _abortNative();
          } finally {
            await _delete(path);
          }
          rethrow;
        }
      });
      return _current(epoch) && recording;
    } finally {
      if (!_closed &&
          epoch == _epoch &&
          (phase == VoiceNotePhase.permission ||
              phase == VoiceNotePhase.starting)) {
        _captured = null;
        _changed(VoiceNotePhase.idle);
      }
    }
  }

  void _stateChanged(RecordState state) {
    if (!recording || state == RecordState.record) return;
    final epoch = _epoch;
    unawaited(() async {
      try {
        final running = await _native(
          () async => await capture.isRecording() && !await capture.isPaused(),
        );
        if (_current(epoch) && recording && !running) await _automaticFinish();
      } catch (_) {
        if (_current(epoch) && recording) await _automaticFinish();
      }
    }());
  }

  Future<void> _automaticFinish() async {
    try {
      await finish();
    } catch (_) {
      if (_owner) {
        error = 'Не удалось сохранить запись. Попробуйте записать ещё раз';
        notifyListeners();
      }
    }
  }

  Future<void> finish() {
    if (phase == VoiceNotePhase.stopping) {
      return _finishing ?? Future<void>.value();
    }
    if (!recording) return Future<void>.value();
    _timer?.cancel();
    final epoch = _epoch, path = _captured!;
    _changed(VoiceNotePhase.stopping);
    late final Future<void> result;
    result =
        _native(() async {
          try {
            await capture.stop();
            if (!_current(epoch)) {
              await _delete(path);
              return;
            }
            if (!await File(path).exists() || await File(path).length() <= 44) {
              throw ApiFailure(
                400,
                'Запись пустая. Попробуйте записать ещё раз',
              );
            }
            if (!_current(epoch)) {
              await _delete(path);
              return;
            }
            _captured = null;
            _draft = path;
            _changed(VoiceNotePhase.ready);
          } catch (_) {
            try {
              await _abortNative();
            } finally {
              await _delete(path);
              if (!_closed && epoch == _epoch) {
                _captured = null;
                _changed(VoiceNotePhase.idle);
              }
            }
            rethrow;
          }
        }).whenComplete(() {
          if (identical(_finishing, result)) _finishing = null;
        });
    _finishing = result;
    return result;
  }

  Future<void> suspend({bool cancelPermission = false}) async {
    if (recording || phase == VoiceNotePhase.stopping) {
      await _automaticFinish();
    } else if (phase == VoiceNotePhase.starting ||
        (cancelPermission && phase == VoiceNotePhase.permission)) {
      await cancel();
    }
  }

  void resume() {
    final resumed = _permissionResume;
    if (resumed != null && !resumed.isCompleted) resumed.complete();
  }

  Future<void> send(Future<void> Function(String path) operation) async {
    if (!canSend) return;
    final epoch = _epoch, path = _draft!;
    final completed = Completer<void>();
    _sends.add(completed.future);
    _leased.add(path);
    _changed(VoiceNotePhase.sending);
    var accepted = false;
    try {
      await operation(path);
      accepted = true;
      if (_current(epoch)) {
        _draft = null;
        _changed(VoiceNotePhase.idle);
      }
    } catch (_) {
      if (_current(epoch)) _changed(VoiceNotePhase.ready);
      rethrow;
    } finally {
      _leased.remove(path);
      try {
        if (accepted || !_current(epoch)) await _delete(path);
      } finally {
        completed.complete();
        _sends.remove(completed.future);
      }
    }
  }

  Future<void> cancel() {
    if (_closed) return _closing ?? Future<void>.value();
    final nativeCapture =
        phase == VoiceNotePhase.starting ||
        recording ||
        phase == VoiceNotePhase.stopping;
    ++_epoch;
    resume();
    _timer?.cancel();
    final paths = _owned.toList();
    _captured = _draft = null;
    error = null;
    _changed(VoiceNotePhase.idle);
    return _native(() async {
      try {
        if (nativeCapture) await _abortNative();
      } finally {
        for (final path in paths) {
          await _delete(path);
        }
      }
    });
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    final nativeCapture =
        phase == VoiceNotePhase.starting ||
        recording ||
        phase == VoiceNotePhase.stopping;
    _closed = true;
    ++_epoch;
    resume();
    phase = VoiceNotePhase.closed;
    _timer?.cancel();
    return _closing = () async {
      Object? failure;
      StackTrace? trace;
      Future<void> attempt(Future<void> Function() action) async {
        try {
          await action();
        } catch (e, s) {
          failure ??= e;
          trace ??= s;
        }
      }

      await attempt(() async => _states?.cancel());
      await _native(() async {
        if (nativeCapture) await attempt(capture.cancel);
        await attempt(capture.close);
      });
      await Future.wait(_sends.toList());
      for (final path in _owned.toList()) {
        await attempt(() => _delete(path));
      }
      if (failure != null) Error.throwWithStackTrace(failure!, trace!);
    }();
  }

  @override
  void dispose() {
    unawaited(
      close().catchError((Object _) {
        debugPrint('MyKIDS: temporary voice cleanup requires retry');
      }),
    );
    super.dispose();
  }
}
