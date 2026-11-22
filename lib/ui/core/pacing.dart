/// Pacing (polish pass, step 6): one animation queue so hops, captures, dice
/// and effects never overlap, the "no legal move" hold, the AI think time and
/// the animation speed. Pure Dart, no Flutter.
///
/// The queue is a gate, not an animator: every timeline (dice, token plan,
/// effects, toasts) still samples the frame clock. The game controller
/// appends a beat for each thing it starts, and nothing new (a roll, an AI
/// action) may start before the queue is free. "Skip" ends the queue now: the
/// controller moves its clock forward by [AnimationQueue.skip]'s result, so
/// every running timeline finishes in the same frame and no effect is left
/// hanging.
library;

import 'dart:math' as math;

import 'motion_spec.dart';

/// What a beat is. Only used to tell them apart (tests, the controller).
enum BeatKind {
  /// The die tumbling, up to the settle.
  roll,

  /// The die at rest showing its face (the reveal ring).
  reveal,

  /// A pause that lets a result be read ("No move").
  hold,

  /// A token hop, capture or finish.
  move,

  /// What is left of the effects after a move (rings, sparks, glow).
  tail,
}

/// One slot of the queue.
class Beat {
  const Beat(this.kind, this.startMs, this.endMs);

  final BeatKind kind;
  final double startMs;
  final double endMs;

  double get durationMs => endMs - startMs;

  @override
  String toString() => 'Beat($kind $startMs..$endMs)';
}

/// A strictly sequential queue of [Beat]s on a millisecond clock.
class AnimationQueue {
  final List<Beat> _beats = [];

  /// Appends a beat of [durationMs] after everything queued; when the queue
  /// has run dry the beat starts at [nowMs]. A zero or negative duration
  /// adds nothing.
  Beat? add(BeatKind kind, double durationMs, double nowMs) {
    if (!(durationMs > 0)) {
      return null;
    }
    _prune(nowMs);
    final start = _beats.isEmpty ? nowMs : _beats.last.endMs;
    final beat = Beat(kind, start, start + durationMs);
    _beats.add(beat);
    return beat;
  }

  /// Whether a beat is running or waiting at [nowMs].
  bool busy(double nowMs) => _beats.any((b) => b.endMs > nowMs);

  /// When the queue is free: the end of the last beat, never before [nowMs].
  double freeAtMs(double nowMs) {
    final last = _beats.isEmpty ? nowMs : _beats.last.endMs;
    return last > nowMs ? last : nowMs;
  }

  /// Time left until the queue is free.
  double remainingMs(double nowMs) => freeAtMs(nowMs) - nowMs;

  /// The beat running at [nowMs], or `null` (between beats and when idle).
  Beat? current(double nowMs) {
    for (final b in _beats) {
      if (b.startMs <= nowMs && nowMs < b.endMs) {
        return b;
      }
    }
    return null;
  }

  /// Beats not finished at [nowMs], in order.
  List<Beat> pending(double nowMs) => [
        for (final b in _beats)
          if (b.endMs > nowMs) b,
      ];

  /// Ends everything queued now. Returns how far the clock has to move
  /// forward for every running timeline to be at its end (`0` when idle).
  double skip(double nowMs) {
    final jump = remainingMs(nowMs);
    _beats.clear();
    return jump;
  }

  /// Forgets everything (a new game).
  void clear() => _beats.clear();

  void _prune(double nowMs) => _beats.removeWhere((b) => b.endMs <= nowMs);

  int get length => _beats.length;
}

/// The animation speed setting. Normal plays the timings of the spec as they
/// are; Fast divides every duration by [factor].
enum AnimationSpeed {
  normal(1),
  fast(1.6);

  const AnimationSpeed(this.factor);

  final double factor;
}

/// The numbers of the pacing.
class Pacing {
  const Pacing._();

  /// With no legal move the roll stays on the table this long (after the die
  /// settles), then the turn passes. Divided by the speed.
  static const double noMoveHoldMs = 600;

  /// The AI waits a random time in this range before it rolls and before it
  /// picks a move (divided by the speed).
  static const double thinkMinMs = 400;
  static const double thinkMaxMs = 900;

  /// A tap skips a running sequence only when more than this is left of it:
  /// a hop that is about to land is not worth cutting short (and a double
  /// tap must not skip the move it just made).
  static const double skipMinRemainingMs = 250;

  /// Reduced motion: a short, fixed think time.
  static const double reducedThinkMs = 250;

  /// How long the "no legal move" roll is shown, counted from the settle.
  static double noMoveMs(MotionSpec spec) =>
      spec.reducedMotion ? reducedThinkMs : noMoveHoldMs / spec.speed;
}

/// The AI's think time: a random delay in [Pacing.thinkMinMs] ..
/// [Pacing.thinkMaxMs], from its own seeded generator (visual only: never the
/// game's dice).
class ThinkDelay {
  ThinkDelay([int seed = 1]) : _random = math.Random(seed);

  final math.Random _random;

  /// The next delay for [spec] (ms).
  double next(MotionSpec spec) {
    if (spec.reducedMotion) {
      return Pacing.reducedThinkMs;
    }
    final span = Pacing.thinkMaxMs - Pacing.thinkMinMs;
    return (Pacing.thinkMinMs + span * _random.nextDouble()) / spec.speed;
  }
}
