import 'package:flutter/widgets.dart';
import 'package:ludo/ui/core/haptics.dart';
import 'package:ludo/ui/core/music_fade.dart';
import 'package:ludo/ui/core/sfx.dart';

import '../settings/game_settings.dart';
import 'audio_backend.dart';
import 'audio_clock.dart';

/// Sound for the whole app (docs/ludo-sound-themes.md section 4).
///
/// - **Lazy:** nothing touches the audio engine until [start], which the app
///   calls after the first frame, never before `runApp`.
/// - **Fails quiet:** any error from the backend turns audio off for the
///   session and is logged with `debugPrint`. The game never notices.
/// - **No queue:** an effect asked for before the service is ready, or while
///   the app is not in the foreground, is dropped.
/// - **Music** is a state, not an event: it plays while a table or replay
///   screen is up ([enterMusicScreen]/[leaveMusicScreen]) and the setting is
///   on, fades in and out over 400 ms, and pauses (with no fade) when the
///   app leaves `resumed`.
///
/// Nothing here reads the game state or touches the dice.
class AudioService with WidgetsBindingObserver {
  AudioService({
    required AudioBackend backend,
    AudioClock? clock,
    bool observeLifecycle = true,
  })  : _backend = backend,
        _clock = clock ?? SystemAudioClock(),
        _observeLifecycle = observeLifecycle {
    _sfx = SfxPlayer(
      emit: _emit,
      schedule: _clock.after,
      nowMs: _clock.nowMs,
    );
  }

  /// Length of one music tick while a fade runs (about one frame).
  static const double fadeTickMs = 16;

  final AudioBackend _backend;
  final AudioClock _clock;
  final bool _observeLifecycle;
  late final SfxPlayer _sfx;
  final MusicFade _fade = MusicFade();

  bool _started = false;
  bool _ready = false;
  bool _failed = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _musicEnabled = false;
  double _musicVolume = defaultMusicVolume;
  int _screens = 0;
  bool _musicRunning = false;
  void Function()? _stopTicker;

  /// Whether the engine is up and sounds are accepted.
  bool get ready => _ready;

  /// Whether audio was turned off for this session by an error.
  bool get failed => _failed;

  /// Whether the music is (fading in, playing or fading out) and not paused.
  bool get musicRunning => _musicRunning;

  // ---- Start-up --------------------------------------------------------

  /// Starts the engine and loads every sound once. Safe to call again.
  /// Call it after the first frame.
  Future<void> start() async {
    if (_started || _failed || _disposed) {
      return;
    }
    _started = true;
    try {
      await _backend.init();
      for (final event in SfxEvent.values) {
        await _backend.loadEffect(
          event,
          '$audioAssetDir/${sfxAssetFile(event)}',
        );
      }
      await _backend.loadMusic('$audioAssetDir/$musicAssetFile');
    } catch (e) {
      _fail('start', e);
      return;
    }
    if (_disposed) {
      return;
    }
    if (_observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
    _ready = true;
    _syncMusic();
  }

  // ---- Settings --------------------------------------------------------

  bool get sfxEnabled => _sfx.enabled;
  set sfxEnabled(bool v) => _sfx.enabled = v;

  double get sfxVolume => _sfx.volume;
  set sfxVolume(double v) => _sfx.volume = v;

  bool get musicEnabled => _musicEnabled;
  set musicEnabled(bool v) {
    if (_musicEnabled == v) {
      return;
    }
    _musicEnabled = v;
    _syncMusic();
  }

  double get musicVolume => _musicVolume;
  set musicVolume(double v) {
    _musicVolume = clampVolume(v);
    _applyMusicVolume();
  }

  /// Applies the four sound settings now and again whenever they change.
  /// Returns the function that stops listening.
  VoidCallback bind(GameSettings settings) {
    void apply() {
      sfxEnabled = settings.sfxEnabled;
      sfxVolume = settings.sfxVolume;
      musicVolume = settings.musicVolume;
      musicEnabled = settings.musicEnabled;
    }

    apply();
    settings.addListener(apply);
    return () => settings.removeListener(apply);
  }

  // ---- Effects ---------------------------------------------------------

  /// Plays [event] (rate-limited, with a little variation; see `SfxPlayer`).
  void play(SfxEvent event) {
    if (_failed) {
      return;
    }
    _sfx.play(event);
  }

  /// Plays the sound that goes with a haptic [event].
  void playHaptic(HapticEvent event) => play(sfxFor(event));

  /// Drops cues still waiting for their delay (a scrub, a pause).
  void cancelPending() => _sfx.cancelPending();

  void _emit(SfxCue cue) {
    if (!_ready || _failed || !_foreground) {
      return; // Dropped, never queued.
    }
    try {
      _backend.playEffect(cue.event, volume: cue.volume, rate: cue.rate);
    } catch (e) {
      _fail('effect ${cue.event.name}', e);
    }
  }

  // ---- Music -----------------------------------------------------------

  /// A screen that plays music (table or replay) is up.
  void enterMusicScreen() {
    _screens++;
    _syncMusic();
  }

  /// That screen is gone. The music fades out when the last one leaves.
  void leaveMusicScreen() {
    if (_screens > 0) {
      _screens--;
    }
    _syncMusic();
  }

  bool get _wantMusic =>
      _ready && !_failed && _musicEnabled && _screens > 0 && _foreground;

  double _effectiveMusicVolume(double level) =>
      clampVolume(_musicVolume * musicGainBelowEffects * level);

  void _syncMusic() {
    if (!_ready || _failed || _disposed) {
      return;
    }
    final now = _clock.nowMs();
    try {
      if (_wantMusic) {
        if (!_musicRunning) {
          _backend.startMusic(_effectiveMusicVolume(_fade.levelAt(now)));
          _musicRunning = true;
        }
        _fade.fadeTo(1, now);
      } else if (_musicRunning) {
        _fade.fadeTo(0, now);
      }
    } catch (e) {
      _fail('music', e);
      return;
    }
    _tick();
  }

  void _applyMusicVolume() {
    if (!_musicRunning || _failed) {
      return;
    }
    try {
      _backend
          .setMusicVolume(_effectiveMusicVolume(_fade.levelAt(_clock.nowMs())));
    } catch (e) {
      _fail('music volume', e);
    }
  }

  void _tick() {
    if (_failed || _disposed) {
      return;
    }
    final now = _clock.nowMs();
    final fading = _fade.isFading(now);
    try {
      if (_musicRunning) {
        _backend.setMusicVolume(_effectiveMusicVolume(_fade.levelAt(now)));
        if (!fading && _fade.target == 0 && !_wantMusic) {
          _backend.pauseMusic();
          _musicRunning = false;
        }
      }
    } catch (e) {
      _fail('music fade', e);
      return;
    }
    if (fading && _stopTicker == null) {
      _stopTicker = _clock.every(fadeTickMs, _tick);
    } else if (!fading) {
      _stopTicker?.call();
      _stopTicker = null;
    }
  }

  // ---- Lifecycle -------------------------------------------------------

  /// Leaving `resumed` pauses the music at once and drops pending effects;
  /// coming back fades the music in again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) {
      return;
    }
    _foreground = foreground;
    if (!foreground) {
      _sfx.cancelPending();
      _stopTicker?.call();
      _stopTicker = null;
      if (_musicRunning && !_failed) {
        _fade.jumpTo(0);
        try {
          _backend.pauseMusic();
        } catch (e) {
          _fail('pause', e);
        }
        _musicRunning = false;
      }
    } else {
      _syncMusic();
    }
  }

  // ---- Failure and teardown -------------------------------------------

  void _fail(String what, Object error) {
    debugPrint('Audio off for this session ($what): $error');
    _failed = true;
    _ready = false;
    _musicRunning = false;
    _stopTicker?.call();
    _stopTicker = null;
    _release();
  }

  Future<void> _release() async {
    try {
      await _backend.dispose();
    } catch (e) {
      debugPrint('Audio release failed: $e');
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _stopTicker?.call();
    _stopTicker = null;
    if (_observeLifecycle && _ready) {
      WidgetsBinding.instance.removeObserver(this);
    }
    final wasReady = _ready;
    _ready = false;
    _musicRunning = false;
    if (wasReady && !_failed) {
      await _release();
    }
  }
}
