import 'dart:async';

import 'package:ludo/ui/core/sfx.dart';
import 'package:ludo_app/audio/audio_backend.dart';
import 'package:ludo_app/audio/audio_clock.dart';

/// An [AudioBackend] that records every call and can be told to fail.
class FakeAudioBackend implements AudioBackend {
  /// When set, [init] waits for it (to test what happens before ready).
  Completer<void>? initGate;

  bool failInit = false;
  bool failLoad = false;
  bool failPlay = false;
  bool failMusic = false;

  int initCalls = 0;
  int disposeCalls = 0;
  int startMusicCalls = 0;
  int pauseMusicCalls = 0;

  final Map<SfxEvent, String> loadedEffects = {};
  String? loadedMusic;
  final List<({SfxEvent event, double volume, double rate})> effects = [];

  /// Every volume sent to the music voice, in order (start and updates).
  final List<double> musicVolumes = [];

  bool musicPlaying = false;

  @override
  Future<void> init() async {
    initCalls++;
    await initGate?.future;
    if (failInit) {
      throw StateError('init failed');
    }
  }

  @override
  Future<void> loadEffect(SfxEvent event, String asset) async {
    if (failLoad) {
      throw StateError('load failed');
    }
    loadedEffects[event] = asset;
  }

  @override
  Future<void> loadMusic(String asset) async {
    if (failLoad) {
      throw StateError('load failed');
    }
    loadedMusic = asset;
  }

  @override
  void playEffect(
    SfxEvent event, {
    required double volume,
    required double rate,
  }) {
    if (failPlay) {
      throw StateError('play failed');
    }
    effects.add((event: event, volume: volume, rate: rate));
  }

  @override
  void startMusic(double volume) {
    if (failMusic) {
      throw StateError('music failed');
    }
    startMusicCalls++;
    musicPlaying = true;
    musicVolumes.add(volume);
  }

  @override
  void setMusicVolume(double volume) {
    if (failMusic) {
      throw StateError('music failed');
    }
    musicVolumes.add(volume);
  }

  @override
  void pauseMusic() {
    pauseMusicCalls++;
    musicPlaying = false;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  double get lastMusicVolume => musicVolumes.isEmpty ? -1 : musicVolumes.last;
}

/// A manual clock: time moves only through [advance], which fires the timers
/// that fall due on the way, in order.
class FakeAudioClock implements AudioClock {
  double _now = 0;
  final List<_Once> _once = [];
  final List<_Every> _every = [];

  @override
  double nowMs() => _now;

  @override
  void after(double delayMs, void Function() action) {
    _once.add(_Once(_now + delayMs, action));
  }

  @override
  void Function() every(double periodMs, void Function() tick) {
    final timer = _Every(_now + periodMs, periodMs, tick);
    _every.add(timer);
    return () => timer.cancelled = true;
  }

  /// Number of periodic timers still running.
  int get activeTickers => _every.where((t) => !t.cancelled).length;

  void advance(double ms) {
    final end = _now + ms;
    while (true) {
      _Once? nextOnce;
      for (final o in _once) {
        if (o.due <= end && (nextOnce == null || o.due < nextOnce.due)) {
          nextOnce = o;
        }
      }
      _Every? nextEvery;
      for (final e in _every) {
        if (!e.cancelled &&
            e.due <= end &&
            (nextEvery == null || e.due < nextEvery.due)) {
          nextEvery = e;
        }
      }
      if (nextOnce == null && nextEvery == null) {
        break;
      }
      if (nextEvery == null ||
          (nextOnce != null && nextOnce.due <= nextEvery.due)) {
        _now = nextOnce!.due;
        _once.remove(nextOnce);
        nextOnce.action();
      } else {
        _now = nextEvery.due;
        nextEvery.due += nextEvery.period;
        nextEvery.tick();
      }
    }
    _now = end;
  }
}

class _Once {
  _Once(this.due, this.action);
  final double due;
  final void Function() action;
}

class _Every {
  _Every(this.due, this.period, this.tick);
  double due;
  final double period;
  final void Function() tick;
  bool cancelled = false;
}
