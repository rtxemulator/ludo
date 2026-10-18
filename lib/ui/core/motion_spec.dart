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
    this.pressScale = 0.9,
    this.liftScaleGain = 0.5,
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
    this.pulsePeriodMs = 900,
    this.pulseMinRadius = 0.62,
    this.pulseRadiusGain = 0.14,
    this.pulseMinOpacity = 0.35,
    this.pulseOpacityGain = 0.55,
    this.dustMs = 160,
    this.dustStartRadius = 0.5,
    this.dustEndRadius = 0.9,
    this.dustOpacity = 0.25,
    this.shockwaveMs = 260,
    this.shockwaveStartRadius = 0.4,
    this.shockwaveEndRadius = 1.2,
    this.shockwaveOpacity = 0.8,
    this.sparkCount = 8,
    this.sparkDistance = 0.9,
    this.sparkMs = 450,
    this.sparkSize = 0.09,
    this.pocketGlowMs = 500,
    this.coinFlipTurns = 1.5,
    this.confettiCount = 60,
    this.confettiMs = 3200,
    this.dockHandoffMs = 200,
    this.ghostOpacity = 0.45,
    this.ghostScale = 0.8,
    this.ghostDesaturate = 0.7,
    this.idleBobPeriodMs = 1600,
    this.idleBobScale = 0.04,
    this.idleHaloOpacity = 0.28,
    this.dockPulseMs = 300,
    this.yardRingMs = 220,
    this.yardRingStartRadius = 1.0,
    this.yardRingEndRadius = 0.4,
    this.yardRingOpacity = 0.7,
    this.rippleMs = 320,
    this.rippleStartRadius = 0.3,
    this.rippleEndRadius = 1.1,
    this.rippleOpacity = 0.6,
    this.nudgeMs = 160,
    this.nudgeAmplitude = 0.07,
    this.nudgeCycles = 2,
    this.nudgeDecay = 3,
    this.nudgeRingMs = 260,
    this.nudgeRingStartRadius = 0.45,
    this.nudgeRingEndRadius = 0.8,
    this.nudgeRingOpacity = 0.55,
    this.noMoveDimMs = 200,
    this.noMoveDimAmount = 0.5,
    this.dieShakeMs = 300,
    this.dieShakeAmplitude = 0.12,
    this.dieShakeCycles = 3,
    this.dieShakeDecay = 3,
    this.toastMs = 1200,
    this.toastFadeMs = 180,
    this.rankBadgeMs = 450,
    this.dice3d = const Dice3dSpec(),
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

  /// Uniform scale at the deepest point of a landing press (1 -> this -> 1).
  final double pressScale;

  /// A token (or die) at height `h` cells is drawn `1 + liftScaleGain * h`
  /// times bigger: height is scale, never a Y offset (section 1 of the UI/UX
  /// doc).
  final double liftScaleGain;

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

  final double pulsePeriodMs;
  final double pulseMinRadius;
  final double pulseRadiusGain;
  final double pulseMinOpacity;
  final double pulseOpacityGain;

  final double dustMs;
  final double dustStartRadius;
  final double dustEndRadius;
  final double dustOpacity;
  final double shockwaveMs;
  final double shockwaveStartRadius;
  final double shockwaveEndRadius;
  final double shockwaveOpacity;
  final int sparkCount;
  final double sparkDistance;
  final double sparkMs;
  final double sparkSize;
  final double pocketGlowMs;

  /// Full turns of the captured token's coin flip.
  final double coinFlipTurns;

  /// Upper bound for confetti particles (budget: <= 60).
  final int confettiCount;
  final double confettiMs;

  /// A seat's die turns from ghost to live (or back) over this long.
  final double dockHandoffMs;

  /// Ghost die (the last result of a seat that is not on turn).
  final double ghostOpacity;
  final double ghostScale;

  /// How much colour a ghost die loses (`0..1`).
  final double ghostDesaturate;

  /// Idle bob of the die that waits to be rolled: scale `1 +- idleBobScale`
  /// over [idleBobPeriodMs]; the halo breathes with it.
  final double idleBobPeriodMs;
  final double idleBobScale;
  final double idleHaloOpacity;

  /// Dock flash when a dock is tapped out of turn.
  final double dockPulseMs;

  /// Yard-exit ring that contracts onto the yard spot as the token rises, and
  /// the ripple at the start square when it lands.
  final double yardRingMs;
  final double yardRingStartRadius;
  final double yardRingEndRadius;
  final double yardRingOpacity;
  final double rippleMs;
  final double rippleStartRadius;
  final double rippleEndRadius;
  final double rippleOpacity;

  /// Illegal-move nudge: `nudgeAmplitude x dampedSine(nudgeCycles)` sideways
  /// over [nudgeMs] and a faint red ring.
  final double nudgeMs;
  final double nudgeAmplitude;
  final double nudgeCycles;
  final double nudgeDecay;
  final double nudgeRingMs;
  final double nudgeRingStartRadius;
  final double nudgeRingEndRadius;
  final double nudgeRingOpacity;

  /// "No legal move": the roller's tokens dim for [noMoveDimMs] (by up to
  /// [noMoveDimAmount] of their opacity) and the die shakes.
  final double noMoveDimMs;
  final double noMoveDimAmount;
  final double dieShakeMs;
  final double dieShakeAmplitude;
  final double dieShakeCycles;
  final double dieShakeDecay;

  /// Toast pill at a dock: total life and the fade at each end.
  final double toastMs;
  final double toastFadeMs;

  /// Game-over rank badge pop-in.
  final double rankBadgeMs;

  /// Numbers of the 3D dice roll.
  final Dice3dSpec dice3d;
}

/// Timing and size of the 3D dice roll (docs/ludo-ui-ux.md section 4.2).
///
/// Times are milliseconds from the start of the roll, heights are board
/// cells.
class Dice3dSpec {
  const Dice3dSpec({
    this.popInMs = 120,
    this.flightEndMs = 420,
    this.bounce2EndMs = 650,
    this.bounce3EndMs = 800,
    this.settleEndMs = 920,
    this.revealEndMs = 1120,
    this.popFromScale = 0.6,
    this.flightApex = 1.6,
    this.bounce2Apex = 0.55,
    this.bounce3Apex = 0.18,
    this.liftScalePerCell = 0.45 / 1.6,
    this.pressScale = 0.96,
    this.pressMs = 60,
    this.wobbleDegrees = 4,
    this.wobbleCycles = 2,
    this.wobbleDecay = 3,
    this.tumbleTurnsA = 2.5,
    this.tumbleTurnsB = 1.5,
    this.landingJitter = 0.15,
    this.handDistance = 1.4,
    this.maxYawDegrees = 40,
    this.dieCells = 1.9,
  });

  final double popInMs;
  final double flightEndMs;
  final double bounce2EndMs;
  final double bounce3EndMs;
  final double settleEndMs;
  final double revealEndMs;

  /// Scale at the first instant of the pop-in (it overshoots to 1.1, then
  /// settles at 1).
  final double popFromScale;

  final double flightApex;
  final double bounce2Apex;
  final double bounce3Apex;

  /// Extra scale per cell of height (+45% at the 1.6 cell apex).
  final double liftScalePerCell;

  /// Uniform press at each of the three impacts.
  final double pressScale;
  final double pressMs;

  final double wobbleDegrees;
  final double wobbleCycles;
  final double wobbleDecay;

  /// Base number of turns about the two tumble axes (jittered per roll).
  final double tumbleTurnsA;
  final double tumbleTurnsB;

  /// Landing spot jitter around the dock centre (cells).
  final double landingJitter;

  /// How far outside the landing spot the die leaves the dock "hand" edge.
  final double handDistance;

  /// The final yaw (rotation about the vertical axis) is within +-this.
  final double maxYawDegrees;

  /// Die edge length in cells.
  final double dieCells;

  /// Moments the die hits the table.
  List<double> get impactsMs => [flightEndMs, bounce2EndMs, bounce3EndMs];
}
