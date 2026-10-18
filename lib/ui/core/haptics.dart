/// Haptic events, their pulse patterns and the playback logic.
///
/// Pure Dart: the Flutter layer only supplies a way to vibrate (a native
/// channel) and a timer. See docs/ludo-ui-ux.md section 9.
library;

/// Feel of one pulse. The native side maps these to the closest
/// `VibrationEffect` (tick / click / heavy click) or a one-shot waveform.
enum HapticKind { tick, click, heavy }

/// One vibration pulse.
class HapticPulse {
  const HapticPulse(this.kind, this.strength, {this.afterMs = 0});

  final HapticKind kind;

  /// `0..1`; honoured where the hardware has amplitude control.
  final double strength;

  /// Delay after the *start* of the previous pulse (after the start of the
  /// event for the first pulse).
  final double afterMs;
}

/// Everything the game can make the phone feel.
enum HapticEvent {
  diceImpact,
  diceSettle,
  tokenLand,
  capture,
  home,
  illegal,
  noMove,
  six,
  win,
}

/// Minimum time between two pulses (a faster burst just blurs).
const double hapticMinGapMs = 30;

/// Pulse patterns per event (section 9 of the UI/UX doc).
///
/// `diceImpact` spans the three bounces of the 3D dice (impacts at 420, 650
/// and 800 ms), so a single call at the first impact is enough.
const Map<HapticEvent, List<HapticPulse>> hapticPatterns = {
  HapticEvent.diceImpact: [
    HapticPulse(HapticKind.tick, 0.9),
    HapticPulse(HapticKind.tick, 0.5, afterMs: 230),
    HapticPulse(HapticKind.tick, 0.25, afterMs: 150),
  ],
  HapticEvent.diceSettle: [HapticPulse(HapticKind.click, 0.8)],
  HapticEvent.tokenLand: [HapticPulse(HapticKind.tick, 0.8)],
  HapticEvent.capture: [
    HapticPulse(HapticKind.heavy, 1),
    HapticPulse(HapticKind.click, 1, afterMs: 80),
  ],
  HapticEvent.home: [
    HapticPulse(HapticKind.click, 0.6),
    HapticPulse(HapticKind.click, 0.8, afterMs: 70),
    HapticPulse(HapticKind.heavy, 1, afterMs: 70),
  ],
  HapticEvent.illegal: [
    HapticPulse(HapticKind.tick, 0.7),
    HapticPulse(HapticKind.tick, 0.7, afterMs: 72),
  ],
  HapticEvent.noMove: [HapticPulse(HapticKind.tick, 0.4)],
  // Follows the settle click of the same roll.
  HapticEvent.six: [HapticPulse(HapticKind.click, 0.7, afterMs: 80)],
  HapticEvent.win: [
    HapticPulse(HapticKind.click, 0.4),
    HapticPulse(HapticKind.click, 0.55, afterMs: 90),
    HapticPulse(HapticKind.click, 0.7, afterMs: 90),
    HapticPulse(HapticKind.click, 0.85, afterMs: 90),
    HapticPulse(HapticKind.heavy, 1, afterMs: 90),
  ],
};

/// Allows a pulse only if the previous one started at least [minGapMs] ago.
class HapticLimiter {
  HapticLimiter({this.minGapMs = hapticMinGapMs});

  final double minGapMs;
  double? _last;

  bool tryAcquire(double nowMs) {
    final last = _last;
    if (last != null && nowMs - last < minGapMs) {
      return false;
    }
    _last = nowMs;
    return true;
  }

  void reset() => _last = null;
}

typedef HapticEmit = void Function(HapticPulse pulse);
typedef HapticSchedule = void Function(double delayMs, void Function() action);

/// Plays events: applies the global toggle and the rate limit and spreads a
/// pattern over time through the injected [schedule].
class HapticPlayer {
  HapticPlayer({
    required this.emit,
    required this.schedule,
    required this.nowMs,
    double minGapMs = hapticMinGapMs,
  }) : _limiter = HapticLimiter(minGapMs: minGapMs);

  final HapticEmit emit;
  final HapticSchedule schedule;
  final double Function() nowMs;
  final HapticLimiter _limiter;

  /// Global toggle; checked again when a delayed pulse fires.
  bool enabled = true;

  void play(HapticEvent event) {
    if (!enabled) {
      return;
    }
    var delay = 0.0;
    for (final pulse in hapticPatterns[event]!) {
      delay += pulse.afterMs;
      if (delay <= 0) {
        _fire(pulse);
      } else {
        schedule(delay, () => _fire(pulse));
      }
    }
  }

  void _fire(HapticPulse pulse) {
    if (!enabled || !_limiter.tryAcquire(nowMs())) {
      return;
    }
    emit(pulse);
  }
}
