import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'ray_raid_model.dart';

abstract class RaidSound {
  void play(RaidEffectKind kind);
  void silence();
  Future<void> dispose();
}

/// Short original effects only. Never claims audio focus or changes call audio.
class RayRaidSound implements RaidSound {
  final bool Function() allowed;
  final _players = <String, AudioPlayer>{};
  final _busy = <String>{};
  final _ready = <String>{};
  int _generation = 0;
  bool _disposed = false;
  RayRaidSound(this.allowed);

  @override
  void play(RaidEffectKind kind) {
    if (_disposed || !allowed()) return;
    final name = switch (kind) {
      RaidEffectKind.shot => 'pulse',
      RaidEffectKind.dash => 'dash',
      RaidEffectKind.shield => 'shield',
      RaidEffectKind.core => 'core',
      RaidEffectKind.win => 'win',
      RaidEffectKind.hit || RaidEffectKind.drone => 'hit',
    };
    if (!_busy.add(name)) return;
    final generation = _generation;
    unawaited(_play(name, generation));
  }

  bool _current(int generation) =>
      !_disposed && generation == _generation && allowed();
  Future<void> _play(String name, int generation) async {
    try {
      var player = _players[name];
      if (player == null) {
        player = AudioPlayer(
          handleAudioSessionActivation: false,
          androidApplyAudioAttributes: false,
        );
        _players[name] = player;
        await player.setVolume(name == 'pulse' ? .14 : .25);
      }
      if (!_ready.contains(name)) {
        if (!_current(generation)) return;
        await player.setAsset('assets/raid/$name.wav');
        _ready.add(name);
      }
      if (!_current(generation)) return;
      await player.seek(Duration.zero);
      if (!_current(generation)) return;
      await player.play();
    } catch (_) {
      // Optional sound failure never interrupts controls or family communication.
    } finally {
      _busy.remove(name);
    }
  }

  @override
  void silence() {
    _generation++;
    for (final player in _players.values) {
      unawaited(player.pause().catchError((_) {}));
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    final players = _players.values.toList();
    _players.clear();
    _ready.clear();
    await Future.wait(
      players.map((p) async {
        try {
          await p.dispose();
        } catch (_) {}
      }),
    );
  }
}
