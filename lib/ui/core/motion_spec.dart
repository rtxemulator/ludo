/// Every tunable animation number in one place (docs/ludo-animation.md).
///
/// Durations are milliseconds, distances are board cells.
class MotionSpec {
  const MotionSpec({
    this.reducedMotion = false,
    this.reducedFadeMs = 120,
    this.hopStepMs = 130,
    this.hopArc = 0.35,
    this.yardExitMs = 220,
    this.yardExitArc = 0.6,
    this.landSquashMs = 100,
    this.squashY = 0.18,
    this.squashX = 0.12,
    this.captureShakeMs = 220,
    this.shakeAmplitude = 0.12,
    this.shakeCycles = 5,
    this.shakeDecay = 5,
    this.captureReturnMs = 420,
    this.captureReturnArc = 1.2,
    this.finishScaleMs = 260,
    this.finishScale = 0.55,
    this.ringMs = 420,
    this.ringStartRadius = 0.5,
    this.ringEndRadius = 1.6,
    this.ringOpacity = 0.8,
    this.diceTumbleMs = 480,
    this.diceSettleMs = 120,
    this.diceTurns = 3,
    this.diceFlickers = 9,
    this.pulsePeriodMs = 900,
    this.pulseMinRadius = 0.62,
    this.pulseRadiusGain = 0.14,
    this.pulseMinOpacity = 0.35,
    this.pulseOpacityGain = 0.55,
  });

  /// Starting values from the plan.
  static const MotionSpec standard = MotionSpec();

  /// For `MediaQuery.disableAnimations`: cross-fades instead of motion.
  static const MotionSpec reduced = MotionSpec(reducedMotion: true);

  final bool reducedMotion;
  final double reducedFadeMs;

  final double hopStepMs;
  final double hopArc;
  final double yardExitMs;
  final double yardExitArc;
  final double landSquashMs;
  final double squashY;
  final double squashX;

  final double captureShakeMs;
  final double shakeAmplitude;
  final double shakeCycles;
  final double shakeDecay;
  final double captureReturnMs;
  final double captureReturnArc;

  final double finishScaleMs;
  final double finishScale;
  final double ringMs;
  final double ringStartRadius;
  final double ringEndRadius;
  final double ringOpacity;

  final double diceTumbleMs;
  final double diceSettleMs;
  final int diceTurns;
  final int diceFlickers;

  final double pulsePeriodMs;
  final double pulseMinRadius;
  final double pulseRadiusGain;
  final double pulseMinOpacity;
  final double pulseOpacityGain;

  /// Total dice animation length.
  double get diceTotalMs =>
      reducedMotion ? reducedFadeMs : diceTumbleMs + diceSettleMs;
}
