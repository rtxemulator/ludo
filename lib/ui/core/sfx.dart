/// Sound events, their rate limits and variation, and the playback logic.
///
/// Pure Dart, like `haptics.dart`: the Flutter layer only supplies a way to
/// play a sound (the audio backend, chat B of Milestone 6) and a timer. See
/// docs/ludo-sound-themes.md.
///
/// Variation (a little pitch and volume jitter so repeated sounds do not
/// feel mechanical) comes from the player's own [Random]. It never touches
/// the engine's `rngState` or its dice.
library;

import 'dart:math' show Random;

import 'haptics.dart';

/// Everything the game can make you hear.
enum SfxEvent {
  diceRoll,
  diceSettle,

  /// One hop step of a token. The only sound with no haptic.
  hop,
  land,
  capture,
  home,
  six,
  win,

  /// A refused tap or a roll with no move.
  illegal,
  select,
}

/// The sound that goes with a haptic event. Total: every haptic event has a
/// sound (both `illegal` and `noMove` play [SfxEvent.illegal]).
SfxEvent sfxFor(HapticEvent event) => switch (event) {
      HapticEvent.diceImpact => SfxEvent.diceRoll,
      HapticEvent.diceSettle => SfxEvent.diceSettle,
      HapticEvent.tokenLand => SfxEvent.land,
      HapticEvent.capture => SfxEvent.capture,
      HapticEvent.home => SfxEvent.home,
      HapticEvent.illegal => SfxEvent.illegal,
      HapticEvent.noMove => SfxEvent.illegal,
      HapticEvent.six => SfxEvent.six,
      HapticEvent.win => SfxEvent.win,
      HapticEvent.select => SfxEvent.select,
    };

/// Folder of the audio assets inside the app package (`app/`). The generator
/// in `tool/audio/` writes them and `app/pubspec.yaml` registers the folder.
const String audioAssetDir = 'assets/audio';

/// File name of the Ogg Opus effect for [event] (inside [audioAssetDir]).
String sfxAssetFile(SfxEvent event) => '${event.name}.opus';

/// File name of the ambient music loop (inside [audioAssetDir]).
const String musicAssetFile = 'music.opus';

/// Music plays about 6 dB below the effects at the same slider value (the
/// loop is normalised to the same loudness as an effect, so this one factor
/// is the whole difference).
const double musicGainBelowEffects = 0.5;

/// Moments (ms after a move starts) at which the hop sound plays: one per
/// hop step, at take-off. `steps` is the number of hops of the mover and
/// `stepMs` the length of one.
List<double> hopSoundTimesMs({required int steps, required double stepMs}) =>
    [for (var i = 0; i < steps; i++) i * stepMs];

/// Minimum time between two plays of the same event (ms).
const Map<SfxEvent, double> sfxMinGapMs = {
  SfxEvent.diceRoll: 300,
  SfxEvent.diceSettle: 100,
  SfxEvent.hop: 60,
  SfxEvent.land: 80,
  SfxEvent.capture: 150,
  SfxEvent.home: 200,
  SfxEvent.six: 200,
  SfxEvent.win: 1500,
  SfxEvent.illegal: 120,
  SfxEvent.select: 40,
};

/// Delay after the call, for sounds that follow another (`six` follows the
/// settle click of the same roll, like its haptic).
const Map<SfxEvent, double> sfxDelayMs = {
  SfxEvent.six: 80,
};

/// How far a cue may stray from the plain sound: playback rate within
/// `1 +/- pitch`, gain within `1 +/- gain`.
class SfxSpread {
  const SfxSpread({this.pitch = 0, this.gain = 0});

  final double pitch;
  final double gain;
}

/// Variation per event. Sounds that carry meaning barely vary.
const Map<SfxEvent, SfxSpread> sfxVariation = {
  SfxEvent.diceRoll: SfxSpread(pitch: 0.03, gain: 0.05),
  SfxEvent.diceSettle: SfxSpread(pitch: 0.02, gain: 0.04),
  SfxEvent.hop: SfxSpread(pitch: 0.06, gain: 0.08),
  SfxEvent.land: SfxSpread(pitch: 0.06, gain: 0.08),
  SfxEvent.capture: SfxSpread(pitch: 0.02, gain: 0.02),
  SfxEvent.home: SfxSpread(pitch: 0.01, gain: 0.02),
  SfxEvent.six: SfxSpread(pitch: 0.01, gain: 0.02),
  SfxEvent.win: SfxSpread(),
  SfxEvent.illegal: SfxSpread(pitch: 0.02, gain: 0.02),
  SfxEvent.select: SfxSpread(pitch: 0.03, gain: 0.05),
};

/// A volume forced into `0..1`; not a number (NaN) becomes 0.
double clampVolume(double v) {
  if (v.isNaN) {
    return 0;
  }
  return v < 0 ? 0 : (v > 1 ? 1 : v);
}

/// One sound to play: what the backend receives.
class SfxCue {
  const SfxCue(this.event, this.volume, this.rate);

  final SfxEvent event;

  /// Final gain in `0..1` (slider value times the variation, clamped).
  final double volume;

  /// Playback-rate factor around 1 (pitch).
  final double rate;

  @override
  String toString() => 'SfxCue($event, volume: $volume, rate: $rate)';
}

typedef SfxEmit = void Function(SfxCue cue);
typedef SfxSchedule = void Function(double delayMs, void Function() action);

/// Plays events: applies the enabled flag, the volume and the per-event rate
/// limit, adds the variation, and spreads delayed cues over time through the
/// injected [schedule].
class SfxPlayer {
  SfxPlayer({
    required this.emit,
    required this.schedule,
    required this.nowMs,
    int? seed,
    Map<SfxEvent, double> minGapMs = sfxMinGapMs,
  })  : _minGapMs = minGapMs,
        _random = Random(seed);

  final SfxEmit emit;
  final SfxSchedule schedule;
  final double Function() nowMs;
  final Map<SfxEvent, double> _minGapMs;

  // Its own generator: never the game's dice.
  final Random _random;
  final Map<SfxEvent, double> _last = {};
  double _volume = 1;

  // Bumped by [cancelPending]: a delayed cue from an older epoch is dropped.
  int _epoch = 0;

  /// Global toggle; checked again when a delayed cue fires.
  bool enabled = true;

  /// Master volume of the effects, `0..1` (setting it clamps). A volume of 0
  /// emits nothing.
  double get volume => _volume;
  set volume(double v) => _volume = clampVolume(v);

  /// Plays the sound that goes with [event].
  void playHaptic(HapticEvent event) => play(sfxFor(event));

  void play(SfxEvent event) {
    if (!enabled) {
      return;
    }
    final delay = sfxDelayMs[event] ?? 0;
    if (delay <= 0) {
      _fire(event);
    } else {
      final epoch = _epoch;
      schedule(delay, () {
        if (epoch == _epoch) {
          _fire(event);
        }
      });
    }
  }

  /// Drops the cues that are waiting for their delay (a scrub or a pause: a
  /// sound must not fire after the moment it belonged to).
  void cancelPending() => _epoch++;

  void _fire(SfxEvent event) {
    if (!enabled || _volume <= 0) {
      return;
    }
    final now = nowMs();
    final last = _last[event];
    if (last != null && now - last < (_minGapMs[event] ?? 0)) {
      return;
    }
    _last[event] = now;
    final spread = sfxVariation[event] ?? const SfxSpread();
    // Two draws per cue whatever the spread, so the sequence of draws does
    // not depend on the tables.
    final pitch = (_random.nextDouble() * 2 - 1) * spread.pitch;
    final gain = (_random.nextDouble() * 2 - 1) * spread.gain;
    emit(SfxCue(event, clampVolume(_volume * (1 + gain)), 1 + pitch));
  }

  /// Forgets the rate-limit history (a new screen, a new game).
  void reset() => _last.clear();
}
