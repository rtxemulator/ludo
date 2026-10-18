/// Visual effect timelines (rings, sparks, glow, coin flip, confetti) as
/// pure functions of time. No Flutter.
///
/// Like every timeline in `lib/ui/core`, `sample(tMs)` takes *global* time
/// and is empty/invisible outside the effect's lifetime, so a painter can ask
/// for any effect at any frame.
library;

import 'dart:math' as math;

import 'curves.dart';
import 'motion_spec.dart';
import 'pt.dart';
import 'seeded.dart';

/// One expanding, fading ring.
class RingFx {
  const RingFx({
    required this.center,
    required this.startMs,
    required this.durationMs,
    required this.startRadius,
    required this.endRadius,
    required this.startOpacity,
    this.visible = true,
  });

  /// Soft dust ring when a token or die lands.
  factory RingFx.dust({
    required Pt center,
    required double startMs,
    MotionSpec spec = MotionSpec.standard,
  }) =>
      RingFx(
        center: center,
        startMs: startMs,
        durationMs: spec.dustMs,
        startRadius: spec.dustStartRadius,
        endRadius: spec.dustEndRadius,
        startOpacity: spec.dustOpacity,
        visible: !spec.reducedMotion,
      );

  /// Impact shockwave when a token captures another.
  factory RingFx.shockwave({
    required Pt center,
    required double startMs,
    MotionSpec spec = MotionSpec.standard,
  }) =>
      RingFx(
        center: center,
        startMs: startMs,
        durationMs: spec.shockwaveMs,
        startRadius: spec.shockwaveStartRadius,
        endRadius: spec.shockwaveEndRadius,
        startOpacity: spec.shockwaveOpacity,
        visible: !spec.reducedMotion,
      );

  /// Ring that contracts onto the yard spot while a token leaves the yard.
  factory RingFx.yardExit({
    required Pt center,
    required double startMs,
    MotionSpec spec = MotionSpec.standard,
  }) =>
      RingFx(
        center: center,
        startMs: startMs,
        durationMs: spec.yardRingMs,
        startRadius: spec.yardRingStartRadius,
        endRadius: spec.yardRingEndRadius,
        startOpacity: spec.yardRingOpacity,
        visible: !spec.reducedMotion,
      );

  /// Ripple at the start square when a token lands there from the yard.
  factory RingFx.ripple({
    required Pt center,
    required double startMs,
    MotionSpec spec = MotionSpec.standard,
  }) =>
      RingFx(
        center: center,
        startMs: startMs,
        durationMs: spec.rippleMs,
        startRadius: spec.rippleStartRadius,
        endRadius: spec.rippleEndRadius,
        startOpacity: spec.rippleOpacity,
        visible: !spec.reducedMotion,
      );

  /// Faint ring around a token that was tapped but cannot move.
  factory RingFx.nudge({
    required Pt center,
    required double startMs,
    MotionSpec spec = MotionSpec.standard,
  }) =>
      RingFx(
        center: center,
        startMs: startMs,
        durationMs: spec.nudgeRingMs,
        startRadius: spec.nudgeRingStartRadius,
        endRadius: spec.nudgeRingEndRadius,
        startOpacity: spec.nudgeRingOpacity,
        visible: !spec.reducedMotion,
      );

  final Pt center;
  final double startMs;
  final double durationMs;
  final double startRadius;
  final double endRadius;
  final double startOpacity;

  /// `false` for reduced motion: the ring never shows.
  final bool visible;

  double get endMs => startMs + durationMs;

  /// Radius (cells) and opacity at global time [tMs]; opacity is 0 outside
  /// the lifetime.
  ({double radius, double opacity}) sample(double tMs) {
    if (!visible || tMs < startMs || tMs >= endMs) {
      return (radius: startRadius, opacity: 0);
    }
    final u = easeOutCubic((tMs - startMs) / durationMs);
    return (
      radius: startRadius + (endRadius - startRadius) * u,
      opacity: startOpacity * (1 - u),
    );
  }
}

/// One spark of a [SparkBurst].
class Spark {
  const Spark({required this.pos, required this.opacity, required this.size});

  final Pt pos;
  final double opacity;

  /// Radius in cells.
  final double size;
}

/// Radial sparks flying out of the pocket when a token reaches home.
class SparkBurst {
  SparkBurst({
    required this.center,
    required this.startMs,
    this.seed = 0,
    this.spec = MotionSpec.standard,
  }) {
    final rnd = Seeded(seed);
    final base = rnd.range(0, 2 * math.pi / spec.sparkCount);
    for (var i = 0; i < spec.sparkCount; i++) {
      _angles.add(base + i * 2 * math.pi / spec.sparkCount);
      _reach.add(rnd.range(0.8, 1.0));
    }
  }

  final Pt center;
  final double startMs;
  final int seed;
  final MotionSpec spec;
  final List<double> _angles = [];
  final List<double> _reach = [];

  double get endMs => startMs + spec.sparkMs;

  /// Sparks alive at global time [tMs] (empty outside the lifetime and in
  /// reduced motion).
  List<Spark> sample(double tMs) {
    if (spec.reducedMotion || tMs < startMs || tMs >= endMs) {
      return const [];
    }
    final u = (tMs - startMs) / spec.sparkMs;
    final dist = spec.sparkDistance * easeOutCubic(u);
    return [
      for (var i = 0; i < _angles.length; i++)
        Spark(
          pos: Pt(
            center.x + math.cos(_angles[i]) * dist * _reach[i],
            center.y + math.sin(_angles[i]) * dist * _reach[i],
          ),
          opacity: 1 - u,
          size: spec.sparkSize * (1 - 0.5 * u),
        ),
    ];
  }
}

/// Glow of the finish pocket: `0..1..0` over [MotionSpec.pocketGlowMs].
double pocketGlow(double tMs, double startMs, MotionSpec spec) {
  if (spec.reducedMotion || tMs < startMs) {
    return 0;
  }
  final u = (tMs - startMs) / spec.pocketGlowMs;
  return u >= 1 ? 0 : math.sin(math.pi * u);
}

/// Horizontal scale of a captured token flipping like a coin:
/// `cos(2 pi turns u)` (the sign is the face; use `.abs()` for the apparent
/// width of a symmetric disc). Starts at 1, crosses 0 three times for the
/// default 1.5 turns, ends at -1.
double coinFlipScaleX(double u, MotionSpec spec) =>
    math.cos(2 * math.pi * spec.coinFlipTurns * clamp01(u));

/// One piece of confetti.
class ConfettiPiece {
  const ConfettiPiece({
    required this.pos,
    required this.rotation,
    required this.size,
    required this.opacity,
    required this.colorIndex,
  });

  final Pt pos;

  /// Radians.
  final double rotation;

  /// Edge length in cells.
  final double size;
  final double opacity;

  /// Index into the painter's colour list.
  final int colorIndex;
}

/// Win confetti: at most [MotionSpec.confettiCount] (<= 60) particles flying
/// radially out of [origin] and fading. Deterministic for a given [seed].
///
/// There is no gravity: at a table there is no "down" (UI/UX doc, section 1).
class ConfettiBurst {
  ConfettiBurst({
    required this.origin,
    required this.startMs,
    this.seed = 0,
    this.colorCount = 4,
    this.spec = MotionSpec.standard,
  }) {
    final n = math.min(spec.confettiCount, 60);
    final rnd = Seeded(seed);
    for (var i = 0; i < n; i++) {
      _p.add(
        _Particle(
          angle: rnd.range(0, 2 * math.pi),
          reach: rnd.range(2.5, 7.5),
          spin: rnd.range(-6, 6),
          phase: rnd.range(0, 2 * math.pi),
          size: rnd.range(0.18, 0.32),
          delayMs: rnd.range(0, 300),
        ),
      );
    }
  }

  final Pt origin;
  final double startMs;
  final int seed;
  final int colorCount;
  final MotionSpec spec;
  final List<_Particle> _p = [];

  int get count => _p.length;

  double get endMs => startMs + spec.confettiMs;

  /// Pieces alive at global time [tMs] (empty outside the lifetime and in
  /// reduced motion).
  List<ConfettiPiece> sample(double tMs) {
    if (spec.reducedMotion || tMs < startMs || tMs >= endMs) {
      return const [];
    }
    final life = spec.confettiMs - 300;
    final out = <ConfettiPiece>[];
    for (var i = 0; i < _p.length; i++) {
      final p = _p[i];
      final u = clamp01((tMs - startMs - p.delayMs) / life);
      if (tMs - startMs < p.delayMs) {
        continue;
      }
      final dist = p.reach * easeOutCubic(u);
      out.add(
        ConfettiPiece(
          pos: Pt(
            origin.x + math.cos(p.angle) * dist,
            origin.y + math.sin(p.angle) * dist,
          ),
          rotation: p.phase + p.spin * u * 3,
          size: p.size,
          // Full for the first 60%, then fades to 0 at the end of life.
          opacity: u < 0.6 ? 1 : 1 - (u - 0.6) / 0.4,
          colorIndex: i % colorCount,
        ),
      );
    }
    return out;
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.reach,
    required this.spin,
    required this.phase,
    required this.size,
    required this.delayMs,
  });

  final double angle;
  final double reach;
  final double spin;
  final double phase;
  final double size;
  final double delayMs;
}

/// Sideways offset (cells) of a token that was tapped but cannot move:
/// `nudgeAmplitude x dampedSine(nudgeCycles)` over [MotionSpec.nudgeMs]; `0`
/// before, after and in reduced motion.
double nudgeOffset(double tMs, double startMs, MotionSpec spec) {
  final u = (tMs - startMs) / spec.nudgeMs;
  if (spec.reducedMotion || u < 0 || u >= 1) {
    return 0;
  }
  return spec.nudgeAmplitude *
      dampedSine(u, cycles: spec.nudgeCycles, decay: spec.nudgeDecay);
}

/// How far the tokens of a seat with no legal move are dimmed: a `0..1..0`
/// bump over [MotionSpec.noMoveDimMs] (`0` outside it). Multiply by
/// [MotionSpec.noMoveDimAmount] for the opacity loss.
double noMoveDim(double tMs, double startMs, MotionSpec spec) {
  final u = (tMs - startMs) / spec.noMoveDimMs;
  if (spec.reducedMotion || u < 0 || u >= 1) {
    return 0;
  }
  return math.sin(math.pi * u);
}

/// Dock-local sideways offset (cells) of the die that shakes because its
/// roll had no legal move; `0` outside [MotionSpec.dieShakeMs] and in
/// reduced motion.
double dieShakeOffset(double tMs, double startMs, MotionSpec spec) {
  final u = (tMs - startMs) / spec.dieShakeMs;
  if (spec.reducedMotion || u < 0 || u >= 1) {
    return 0;
  }
  return spec.dieShakeAmplitude *
      dampedSine(u, cycles: spec.dieShakeCycles, decay: spec.dieShakeDecay);
}

/// Look of a toast pill [startMs]..`+toastMs`: fades in and out over
/// [MotionSpec.toastFadeMs] and pops in slightly (reduced motion: fade only).
({double opacity, double scale}) toastLook(
  double tMs,
  double startMs,
  MotionSpec spec,
) {
  final t = tMs - startMs;
  if (t < 0 || t >= spec.toastMs) {
    return (opacity: 0, scale: 1);
  }
  final fadeIn = clamp01(t / spec.toastFadeMs);
  final fadeOut = clamp01((spec.toastMs - t) / spec.toastFadeMs);
  final scale = spec.reducedMotion ? 1.0 : 0.85 + 0.15 * easeOutBack(fadeIn);
  return (opacity: math.min(fadeIn, fadeOut), scale: scale);
}

/// Pop-in scale of a game-over rank badge (overshoots, settles at 1); `0`
/// before [startMs]. Reduced motion: always full size.
double rankBadgeScale(double tMs, double startMs, MotionSpec spec) {
  if (spec.reducedMotion) {
    return 1;
  }
  if (tMs < startMs) {
    return 0;
  }
  return easeOutBack((tMs - startMs) / spec.rankBadgeMs);
}
