/// The volume curve of the music voice: a linear fade between "silent" and
/// "full" (docs/ludo-sound-themes.md section 4).
///
/// Pure Dart. The app's `AudioService` samples [levelAt] on a short timer and
/// sends `level * slider * musicGainBelowEffects` to the audio backend.
library;

import 'sfx.dart' show clampVolume;

class MusicFade {
  /// A fade whose full swing (0 to 1) takes [durationMs]. A partial swing
  /// (a screen left again halfway through a fade) takes proportionally less,
  /// so the rate of change is always the same.
  MusicFade({this.durationMs = 400, double level = 0})
      : _from = clampVolume(level),
        _to = clampVolume(level);

  final double durationMs;

  double _from;
  double _to;
  double _startMs = 0;

  /// Where the fade is heading (0 or 1 in use, any `0..1` allowed).
  double get target => _to;

  /// The level (`0..1`) at [nowMs].
  double levelAt(double nowMs) {
    if (_from == _to) {
      return _to;
    }
    final span = (_to - _from).abs() * durationMs;
    if (span <= 0) {
      return _to;
    }
    final u = ((nowMs - _startMs) / span).clamp(0.0, 1.0);
    return u >= 1 ? _to : _from + (_to - _from) * u;
  }

  /// Whether the level at [nowMs] has not reached the target yet.
  bool isFading(double nowMs) => levelAt(nowMs) != _to;

  /// Starts fading to [target] from wherever the level is at [nowMs]. A fade
  /// already heading there is left alone.
  void fadeTo(double target, double nowMs) {
    final goal = clampVolume(target);
    if (goal == _to) {
      return;
    }
    _from = levelAt(nowMs);
    _to = goal;
    _startMs = nowMs;
  }

  /// Sets the level at once (no fade), e.g. when the app goes to the
  /// background and the music is paused.
  void jumpTo(double level) {
    _from = _to = clampVolume(level);
  }
}
