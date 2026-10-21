/// Token motion as pure functions of time. No Flutter.
library;

import 'dart:math' as math;

import 'curves.dart';
import 'fx.dart' show coinFlipScaleX;
import 'motion_spec.dart';
import 'pt.dart';

/// What a token looks like at one instant (grid units).
class TokenPose {
  const TokenPose({
    required this.pos,
    this.lift = 0,
    this.scale = 1,
    this.opacity = 1,
    this.flipX = 1,
  });

  /// Ground position (where the shadow is).
  final Pt pos;

  /// Height above the ground, in cells (>= 0). Drives the shadow only; the
  /// token itself is never moved up the screen (it has no "up" at a table).
  final double lift;

  /// Uniform scale of the token: height (`1 + liftScaleGain * lift`), the
  /// landing press and the finish shrink are all folded into this one number.
  final double scale;
  final double opacity;

  /// Apparent width factor `0..1` of the token: a captured token flips like
  /// a coin on its way home (the painter squeezes the disc horizontally).
  /// `1` for every other pose.
  final double flipX;
}

double _heightScale(MotionSpec spec, double lift) =>
    1 + spec.liftScaleGain * lift;

/// A token animation: [sample] is pure, so it can be queried at any time in
/// any order.
class TokenTimeline {
  TokenTimeline._(this.durationMs, this.impactMs, this._sample);

  /// Hops along [path] (`path.first` = current spot, `path.last` = target).
  ///
  /// [fromYard] uses the single higher exit hop (path must have 2 points);
  /// [toFinish] ends with the shrink-to-pocket instead of the landing squash.
  factory TokenTimeline.hop({
    required List<Pt> path,
    bool fromYard = false,
    bool toFinish = false,
    MotionSpec spec = MotionSpec.standard,
  }) {
    assert(path.length >= 2, 'a hop needs a start and an end');
    assert(!fromYard || path.length == 2, 'yard exit is a single hop');
    if (spec.reducedMotion) {
      return TokenTimeline.jump(from: path.first, to: path.last, spec: spec);
    }
    final steps = path.length - 1;
    final stepMs = fromYard ? spec.yardExitMs : spec.hopStepMs;
    final arcHeight = fromYard ? spec.yardExitArc : spec.hopArc;
    final hopsEnd = steps * stepMs;
    final tail = toFinish ? spec.finishScaleMs : spec.landSquashMs;

    TokenPose sample(double t) {
      if (t < hopsEnd) {
        final i = math.min(steps - 1, (t / stepMs).floor());
        final u = (t - i * stepMs) / stepMs;
        final lift = arc(u, arcHeight);
        return TokenPose(
          pos: Pt.lerp(path[i], path[i + 1], u),
          lift: lift,
          scale: _heightScale(spec, lift),
        );
      }
      final u = (t - hopsEnd) / tail;
      if (toFinish) {
        final s = 1 + (spec.finishScale - 1) * easeOutBack(u);
        return TokenPose(pos: path.last, scale: s);
      }
      // Uniform press (1 -> pressScale -> 1), not a vertical squash.
      final bump = math.sin(math.pi * clamp01(u));
      return TokenPose(
        pos: path.last,
        scale: 1 - (1 - spec.pressScale) * bump,
      );
    }

    return TokenTimeline._(hopsEnd + tail, hopsEnd, sample);
  }

  /// A captured token: impact shake in place, then a flight back to [yard].
  factory TokenTimeline.captured({
    required Pt square,
    required Pt yard,
    MotionSpec spec = MotionSpec.standard,
  }) {
    if (spec.reducedMotion) {
      return TokenTimeline.jump(from: square, to: yard, spec: spec);
    }
    final flightEnd = spec.captureShakeMs + spec.captureReturnMs;
    TokenPose sample(double t) {
      if (t < spec.captureShakeMs) {
        final u = t / spec.captureShakeMs;
        final dx = spec.shakeAmplitude *
            dampedSine(u, cycles: spec.shakeCycles, decay: spec.shakeDecay);
        return TokenPose(pos: Pt(square.x + dx, square.y));
      }
      if (t < flightEnd) {
        final u = (t - spec.captureShakeMs) / spec.captureReturnMs;
        final lift = arc(u, spec.captureReturnArc);
        return TokenPose(
          pos: Pt.lerp(square, yard, easeInOutCubic(u)),
          lift: lift,
          scale: _heightScale(spec, lift),
          // Never exactly 0: a zero-width disc is a singular matrix.
          flipX: math.max(0.04, coinFlipScaleX(u, spec).abs()),
        );
      }
      // Lands in the yard with the same uniform press as any landing.
      final u = (t - flightEnd) / spec.landSquashMs;
      final bump = math.sin(math.pi * clamp01(u));
      return TokenPose(
        pos: yard,
        scale: 1 - (1 - spec.pressScale) * bump,
      );
    }

    return TokenTimeline._(flightEnd + spec.landSquashMs, 0, sample);
  }

  /// Reduced-motion move: fade out at [from], fade in at [to].
  factory TokenTimeline.jump({
    required Pt from,
    required Pt to,
    MotionSpec spec = MotionSpec.standard,
  }) {
    final fade = spec.reducedFadeMs;
    TokenPose sample(double t) {
      if (t < fade) {
        return TokenPose(pos: from, opacity: 1 - clamp01(t / fade));
      }
      return TokenPose(pos: to, opacity: clamp01((t - fade) / fade));
    }

    return TokenTimeline._(fade * 2, fade, sample);
  }

  /// A gentle glide from [from] to [to] (a banked-rolls revert): one arc of
  /// [MotionSpec.revertArc] cells over [MotionSpec.revertMs] and the usual
  /// landing press. Reduced motion cross-fades like [TokenTimeline.jump].
  factory TokenTimeline.glide({
    required Pt from,
    required Pt to,
    MotionSpec spec = MotionSpec.standard,
  }) {
    if (spec.reducedMotion) {
      return TokenTimeline.jump(from: from, to: to, spec: spec);
    }
    final flight = spec.revertMs;
    TokenPose sample(double t) {
      if (t < flight) {
        final u = t / flight;
        final lift = arc(u, spec.revertArc);
        return TokenPose(
          pos: Pt.lerp(from, to, easeInOutCubic(u)),
          lift: lift,
          scale: _heightScale(spec, lift),
        );
      }
      final u = (t - flight) / spec.landSquashMs;
      final bump = math.sin(math.pi * clamp01(u));
      return TokenPose(
        pos: to,
        scale: 1 - (1 - spec.pressScale) * bump,
      );
    }

    return TokenTimeline._(flight + spec.landSquashMs, flight, sample);
  }

  /// Total length in milliseconds.
  final double durationMs;

  /// Moment the token lands on its target (a capture starts here).
  final double impactMs;

  final TokenPose Function(double tMs) _sample;

  TokenPose sample(double tMs) =>
      _sample(tMs < 0 ? 0 : (tMs > durationMs ? durationMs : tMs));
}

/// Expanding ring drawn when a token reaches home.
class RingBurst {
  const RingBurst({
    required this.center,
    required this.startMs,
    required this.spec,
  });

  final Pt center;
  final double startMs;
  final MotionSpec spec;

  double get endMs => startMs + spec.ringMs;

  /// Ring state at global time [tMs]; opacity is 0 outside its lifetime.
  ({double radius, double opacity}) sample(double tMs) {
    if (spec.reducedMotion || tMs < startMs || tMs >= endMs) {
      return (radius: spec.ringStartRadius, opacity: 0);
    }
    final u = easeOutCubic((tMs - startMs) / spec.ringMs);
    return (
      radius: spec.ringStartRadius +
          (spec.ringEndRadius - spec.ringStartRadius) * u,
      opacity: spec.ringOpacity * (1 - u),
    );
  }
}
