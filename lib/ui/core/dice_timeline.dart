/// Dice roll animation as a pure function of time.
library;

import 'dart:math' as math;

import 'curves.dart';
import 'motion_spec.dart';

/// What the dice looks like at one instant.
class DicePose {
  const DicePose({
    required this.face,
    required this.angle,
    required this.scale,
    this.opacity = 1,
  });

  /// Pip count shown (`1..6`).
  final int face;

  /// Rotation in radians; `0` is upright.
  final double angle;
  final double scale;
  final double opacity;
}

/// Timeline of one roll. The outcome [value] is already decided by the
/// engine; the animation only reveals it (never shows it before the end of
/// the tumble).
class DiceTimeline {
  DiceTimeline({required this.value, this.spec = MotionSpec.standard})
      : assert(value >= 1 && value <= 6);

  final int value;
  final MotionSpec spec;

  double get durationMs => spec.diceTotalMs;

  DicePose sample(double tMs) {
    final t = tMs < 0 ? 0.0 : (tMs > durationMs ? durationMs : tMs);
    if (spec.reducedMotion) {
      return DicePose(
        face: value,
        angle: 0,
        scale: 1,
        opacity: clamp01(t / spec.reducedFadeMs),
      );
    }
    if (t < spec.diceTumbleMs) {
      final u = t / spec.diceTumbleMs;
      final eased = easeOutCubic(u);
      final k = (eased * spec.diceFlickers).floor();
      // Offset 1..5 from the real value: never the result, and two
      // consecutive offsets always differ, so the face always changes.
      final offset = ((spec.diceFlickers - k) * 2) % 5 + 1;
      final face = (value - 1 + offset) % 6 + 1;
      return DicePose(
        face: face,
        angle: (1 - eased) * spec.diceTurns * 2 * math.pi,
        scale: 1 + 0.15 * math.sin(math.pi * u),
      );
    }
    final s = (t - spec.diceTumbleMs) / spec.diceSettleMs;
    return DicePose(
      face: value,
      angle: 0,
      scale: 1 + 0.06 * dampedSine(s, cycles: 1.5, decay: 4),
    );
  }
}

/// Legal-move pulse (shared by every highlighted token).
class PulseSample {
  const PulseSample({required this.radius, required this.opacity});

  /// Ring radius in cells.
  final double radius;
  final double opacity;

  static PulseSample at(double tMs, MotionSpec spec) {
    final phase = (tMs % spec.pulsePeriodMs) / spec.pulsePeriodMs;
    final w = easeInOutSine(phase < 0.5 ? phase * 2 : (1 - phase) * 2);
    return PulseSample(
      radius: spec.pulseMinRadius + spec.pulseRadiusGain * w,
      opacity: spec.pulseMinOpacity + spec.pulseOpacityGain * w,
    );
  }
}
