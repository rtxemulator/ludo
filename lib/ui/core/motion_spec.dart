/// Every tunable animation number in one place (docs/ludo-animation.md).
///
/// Durations are milliseconds, distances are board cells.
class MotionSpec {
  const MotionSpec({
    this.reducedMotion = false,
    this.speed = 1,
    this.reducedFadeMs = 120,
    this.hopStepMs = 130,
    this.hopArc = 0.35,
    this.yardExitMs = 220,
    this.yardExitArc = 0.6,
    this.landSquashMs = 100,
    this.pressScale = 0.86,
    this.liftScaleGain = 0.5,
    this.captureShakeMs = 220,
    this.shakeAmplitude = 0.08,
    this.shakeCycles = 5,
    this.shakeDecay = 5,
    this.captureReturnMs = 420,
    this.captureReturnArc = 1.2,
    this.captureBow = 0.2,
    this.captureBowMax = 1.2,
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
    this.sparkCount = 14,
    this.sparkDistance = 1.2,
    this.sparkMs = 520,
    this.sparkSize = 0.085,
    this.sparkTail = 0.22,
    this.pocketGlowMs = 500,
    this.coinFlipTurns = 1.5,
    this.confettiCount = 26,
    this.maxParticles = 40,
    this.movableLift = 0.24,
    this.confettiMs = 3200,
    this.dockHandoffMs = 200,
    this.ghostOpacity = 0.4,
    this.ghostScale = 0.72,
    this.ghostDesaturate = 0,
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
    this.toastBigMs = 2200,
    this.rankBadgeMs = 450,
    this.revertMs = 380,
    this.revertArc = 0.5,
    this.revertStaggerMs = 40,
    this.rewindStepMs = 60,
    this.rewindMinMs = 300,
    this.rewindMaxMs = 900,
    this.rewindLift = 0.14,
    this.dice3d = const Dice3dSpec(),
    this.tray = const TraySpec(),
  });

  /// Starting values from the plan.
  static const MotionSpec standard = MotionSpec();

  /// For `MediaQuery.disableAnimations`: cross-fades instead of motion.
  static const MotionSpec reduced = MotionSpec(reducedMotion: true);

  final bool reducedMotion;

  /// How many times faster than [standard] this spec plays (`1` normal).
  /// The AI think time divides by it too.
  final double speed;
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

  /// The flight home of a captured token bows sideways (away from the
  /// board centre) by [captureBow] of its length, at most [captureBowMax]
  /// cells, so it flies along an arc and not along a ruler.
  final double captureBow;
  final double captureBowMax;

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

  /// Length (cells) of the streak a home spark leaves behind it.
  final double sparkTail;
  final double pocketGlowMs;

  /// Full turns of the captured token's coin flip.
  final double coinFlipTurns;

  /// Upper bound for confetti particles (budget: <= 60).
  final int confettiCount;

  /// Particles alive at once, over every effect (home sparks and confetti
  /// can overlap at game over): confetti plus one spark burst stays within it.
  final int maxParticles;

  /// Height (cells) a token that can move rises to at the top of the
  /// pulse; it is drawn `1 + liftScaleGain * lift` bigger (height = scale).
  final double movableLift;
  final double confettiMs;

  /// A seat's die turns from ghost to live (or back) over this long.
  final double dockHandoffMs;

  /// Ghost die (the last result of a seat that is not on turn).
  final double ghostOpacity;
  final double ghostScale;

  /// How much colour a ghost die loses (`0..1`). Zero: a ghost keeps its
  /// seat's colour (it only fades), so it never turns muddy grey.
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

  /// Life of a big toast (a notice with a one-line reason, such as
  /// "Turn undone"); it fades like a small one.
  final double toastBigMs;

  /// Game-over rank badge pop-in.
  final double rankBadgeMs;

  /// A banked-rolls dead end: every token of the turn glides back to where
  /// it started (one glide of [revertMs] with an [revertArc] cell arc, the
  /// next token [revertStaggerMs] later).
  final double revertMs;
  final double revertArc;
  final double revertStaggerMs;

  /// The rewind of a dead end: a token slides back along its own path at
  /// one step per [rewindStepMs], but never faster than [rewindMinMs] or
  /// slower than [rewindMaxMs] in all; [rewindLift] is its (scale) height.
  final double rewindStepMs;
  final double rewindMinMs;
  final double rewindMaxMs;
  final double rewindLift;

  /// Numbers of the 3D dice roll.
  final Dice3dSpec dice3d;

  /// Numbers of the banked-roll tray (docs/ludo-ui-ux.md section 10).
  final TraySpec tray;

  /// A copy that plays [factor] times as fast: every duration (hops, rings,
  /// the dice roll, the roll tray) is divided by [factor]. Distances, sizes
  /// and the periods of the idle breathing (legal-move pulse, idle die bob)
  /// stay as they are, so a faster table does not make the waiting state
  /// jittery. Reduced motion keeps its own near-instant timings.
  MotionSpec scaled(double factor) {
    assert(factor > 0);
    if (factor == 1) {
      return this;
    }
    return MotionSpec(
      reducedMotion: reducedMotion,
      speed: speed * factor,
      reducedFadeMs: reducedFadeMs,
      hopStepMs: hopStepMs / factor,
      hopArc: hopArc,
      yardExitMs: yardExitMs / factor,
      yardExitArc: yardExitArc,
      landSquashMs: landSquashMs / factor,
      pressScale: pressScale,
      liftScaleGain: liftScaleGain,
      captureShakeMs: captureShakeMs / factor,
      shakeAmplitude: shakeAmplitude,
      shakeCycles: shakeCycles,
      shakeDecay: shakeDecay,
      captureReturnMs: captureReturnMs / factor,
      captureReturnArc: captureReturnArc,
      captureBow: captureBow,
      captureBowMax: captureBowMax,
      finishScaleMs: finishScaleMs / factor,
      finishScale: finishScale,
      ringMs: ringMs / factor,
      ringStartRadius: ringStartRadius,
      ringEndRadius: ringEndRadius,
      ringOpacity: ringOpacity,
      pulsePeriodMs: pulsePeriodMs,
      pulseMinRadius: pulseMinRadius,
      pulseRadiusGain: pulseRadiusGain,
      pulseMinOpacity: pulseMinOpacity,
      pulseOpacityGain: pulseOpacityGain,
      dustMs: dustMs / factor,
      dustStartRadius: dustStartRadius,
      dustEndRadius: dustEndRadius,
      dustOpacity: dustOpacity,
      shockwaveMs: shockwaveMs / factor,
      shockwaveStartRadius: shockwaveStartRadius,
      shockwaveEndRadius: shockwaveEndRadius,
      shockwaveOpacity: shockwaveOpacity,
      sparkCount: sparkCount,
      sparkDistance: sparkDistance,
      sparkMs: sparkMs / factor,
      sparkSize: sparkSize,
      sparkTail: sparkTail,
      pocketGlowMs: pocketGlowMs / factor,
      coinFlipTurns: coinFlipTurns,
      confettiCount: confettiCount,
      maxParticles: maxParticles,
      movableLift: movableLift,
      confettiMs: confettiMs / factor,
      dockHandoffMs: dockHandoffMs / factor,
      ghostOpacity: ghostOpacity,
      ghostScale: ghostScale,
      ghostDesaturate: ghostDesaturate,
      idleBobPeriodMs: idleBobPeriodMs,
      idleBobScale: idleBobScale,
      idleHaloOpacity: idleHaloOpacity,
      dockPulseMs: dockPulseMs / factor,
      yardRingMs: yardRingMs / factor,
      yardRingStartRadius: yardRingStartRadius,
      yardRingEndRadius: yardRingEndRadius,
      yardRingOpacity: yardRingOpacity,
      rippleMs: rippleMs / factor,
      rippleStartRadius: rippleStartRadius,
      rippleEndRadius: rippleEndRadius,
      rippleOpacity: rippleOpacity,
      nudgeMs: nudgeMs / factor,
      nudgeAmplitude: nudgeAmplitude,
      nudgeCycles: nudgeCycles,
      nudgeDecay: nudgeDecay,
      nudgeRingMs: nudgeRingMs / factor,
      nudgeRingStartRadius: nudgeRingStartRadius,
      nudgeRingEndRadius: nudgeRingEndRadius,
      nudgeRingOpacity: nudgeRingOpacity,
      noMoveDimMs: noMoveDimMs / factor,
      noMoveDimAmount: noMoveDimAmount,
      dieShakeMs: dieShakeMs / factor,
      dieShakeAmplitude: dieShakeAmplitude,
      dieShakeCycles: dieShakeCycles,
      dieShakeDecay: dieShakeDecay,
      toastMs: toastMs / factor,
      toastFadeMs: toastFadeMs / factor,
      toastBigMs: toastBigMs / factor,
      rankBadgeMs: rankBadgeMs / factor,
      revertMs: revertMs / factor,
      revertArc: revertArc,
      revertStaggerMs: revertStaggerMs / factor,
      rewindStepMs: rewindStepMs / factor,
      rewindMinMs: rewindMinMs / factor,
      rewindMaxMs: rewindMaxMs / factor,
      rewindLift: rewindLift,
      dice3d: dice3d.scaled(factor),
      tray: tray.scaled(factor),
    );
  }
}

/// Timing and size of the banked-roll tray: the die chips beside a dock.
///
/// Times are milliseconds, sizes are in chip edges (one chip = `1`).
class TraySpec {
  const TraySpec({
    this.popMs = 200,
    this.popFromScale = 0.4,
    this.slideMs = 160,
    this.selectMs = 120,
    this.selectedScale = 1.18,
    this.spendMs = 300,
    this.spendEndScale = 0.5,
    this.spendDissolveFrom = 0.65,
    this.spendArc = 0.35,
    this.wipeMs = 340,
    this.wipeStaggerMs = 45,
    this.wipeShake = 0.12,
    this.wipeEndScale = 1.3,
    this.revertMs = 300,
    this.revertStaggerMs = 30,
    this.revertEndScale = 0.6,
    this.promptMs = 360,
    this.promptScale = 0.12,
    this.shakeMs = 300,
    this.shakeAmplitude = 0.16,
    this.shakeCycles = 3,
    this.shakeDecay = 3,
    this.autoSpendMs = 280,
    this.chipGap = 0.12,
    this.fanTilt = 0.06,
    this.fanMaxTilt = 0.3,
    this.fanSag = 0.04,
    this.dimOpacity = 0.45,
  });

  /// A new chip pops in: grows from [popFromScale], overshoots, settles.
  final double popMs;
  final double popFromScale;

  /// The other chips glide to their new slots over this long.
  final double slideMs;

  /// A chip lifts to [selectedScale] (and glows) over [selectMs].
  final double selectMs;
  final double selectedScale;

  /// A spent chip flies to its token over [spendMs], shrinking to
  /// [spendEndScale] and dissolving over the last `1 - spendDissolveFrom`
  /// of the flight; [spendArc] is its extra (scale) height mid-flight.
  final double spendMs;
  final double spendEndScale;
  final double spendDissolveFrom;
  final double spendArc;

  /// Triple-six wipe: each chip shakes then bursts (grows to [wipeEndScale]
  /// while fading) over [wipeMs]; chips start [wipeStaggerMs] apart.
  final double wipeMs;
  final double wipeStaggerMs;
  final double wipeShake;
  final double wipeEndScale;

  /// Dead-end revert: chips shrink and fade over [revertMs].
  final double revertMs;
  final double revertStaggerMs;
  final double revertEndScale;

  /// "Pick a die" prompt: every chip swells by [promptScale] and back.
  final double promptMs;
  final double promptScale;

  /// Whole-tray sideways shake (bank-full tap, tap on an unplayable chip).
  final double shakeMs;
  final double shakeAmplitude;
  final double shakeCycles;
  final double shakeDecay;

  /// A forced single move is spent this long after its chip appeared, so
  /// the chip is seen first.
  final double autoSpendMs;

  /// Gap between chips in the row, and the fan: tilt per slot (radians,
  /// capped by [fanMaxTilt]) and the sag of the outer chips.
  final double chipGap;
  final double fanTilt;
  final double fanMaxTilt;
  final double fanSag;

  /// Opacity of a chip that cannot be spent right now.
  final double dimOpacity;

  /// A copy whose durations are divided by [factor].
  TraySpec scaled(double factor) {
    return TraySpec(
      popMs: popMs / factor,
      popFromScale: popFromScale,
      slideMs: slideMs / factor,
      selectMs: selectMs / factor,
      selectedScale: selectedScale,
      spendMs: spendMs / factor,
      spendEndScale: spendEndScale,
      spendDissolveFrom: spendDissolveFrom,
      spendArc: spendArc,
      wipeMs: wipeMs / factor,
      wipeStaggerMs: wipeStaggerMs / factor,
      wipeShake: wipeShake,
      wipeEndScale: wipeEndScale,
      revertMs: revertMs / factor,
      revertStaggerMs: revertStaggerMs / factor,
      revertEndScale: revertEndScale,
      promptMs: promptMs / factor,
      promptScale: promptScale,
      shakeMs: shakeMs / factor,
      shakeAmplitude: shakeAmplitude,
      shakeCycles: shakeCycles,
      shakeDecay: shakeDecay,
      autoSpendMs: autoSpendMs / factor,
      chipGap: chipGap,
      fanTilt: fanTilt,
      fanMaxTilt: fanMaxTilt,
      fanSag: fanSag,
      dimOpacity: dimOpacity,
    );
  }
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

  /// A copy whose durations are divided by [factor].
  Dice3dSpec scaled(double factor) {
    return Dice3dSpec(
      popInMs: popInMs / factor,
      flightEndMs: flightEndMs / factor,
      bounce2EndMs: bounce2EndMs / factor,
      bounce3EndMs: bounce3EndMs / factor,
      settleEndMs: settleEndMs / factor,
      revealEndMs: revealEndMs / factor,
      popFromScale: popFromScale,
      flightApex: flightApex,
      bounce2Apex: bounce2Apex,
      bounce3Apex: bounce3Apex,
      liftScalePerCell: liftScalePerCell,
      pressScale: pressScale,
      pressMs: pressMs / factor,
      wobbleDegrees: wobbleDegrees,
      wobbleCycles: wobbleCycles,
      wobbleDecay: wobbleDecay,
      tumbleTurnsA: tumbleTurnsA,
      tumbleTurnsB: tumbleTurnsB,
      landingJitter: landingJitter,
      handDistance: handDistance,
      maxYawDegrees: maxYawDegrees,
      dieCells: dieCells,
    );
  }
}
