/// How a seat's die looks between rolls: ghost (last result of a seat that
/// is not on turn) versus live, with the handoff in between, the idle bob of
/// the die waiting to be rolled and the out-of-turn dock flash.
/// Pure Dart, no Flutter. Spec: docs/ludo-ui-ux.md section 4.1.
library;

import 'dart:math' as math;

import 'curves.dart';
import 'motion_spec.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;

class DockLook {
  const DockLook({
    required this.opacity,
    required this.scale,
    required this.desaturate,
    required this.halo,
  });

  /// Look at [live] (`0` = ghost, `1` = live). [idle] means the die waits to
  /// be rolled: it bobs (a scale wobble, never a Y offset) and has a halo.
  factory DockLook.sample({
    required double live,
    required bool idle,
    required double tMs,
    MotionSpec spec = MotionSpec.standard,
  }) {
    final l = clamp01(live);
    var scale = _lerp(spec.ghostScale, 1, l);
    var halo = 0.0;
    if (idle) {
      if (spec.reducedMotion) {
        halo = spec.idleHaloOpacity * l;
      } else {
        final phase = math.sin(2 * math.pi * tMs / spec.idleBobPeriodMs);
        scale *= 1 + spec.idleBobScale * phase;
        halo = spec.idleHaloOpacity * l * (0.75 + 0.25 * phase);
      }
    }
    return DockLook(
      opacity: _lerp(spec.ghostOpacity, 1, l),
      scale: scale,
      desaturate: _lerp(spec.ghostDesaturate, 0, l),
      halo: halo,
    );
  }

  final double opacity;
  final double scale;

  /// `0..1`: how far the colour is pulled toward grey.
  final double desaturate;

  /// Halo strength `0..1` (0 when not idle).
  final double halo;

  /// How live a seat's die is, [sinceMs] after the active seat last changed:
  /// the seat that became active rises `0 -> 1`, the one that stopped being
  /// active falls `1 -> 0`, everyone else stays ghost.
  static double live({
    required bool active,
    required bool wasActive,
    required double sinceMs,
    MotionSpec spec = MotionSpec.standard,
  }) {
    final u = spec.reducedMotion
        ? (sinceMs >= 0 ? 1.0 : 0.0)
        : easeOutCubic(clamp01(sinceMs / spec.dockHandoffMs));
    if (active) {
      return u;
    }
    return wasActive ? 1 - u : 0;
  }

  /// Dock flash strength `1 -> 0` over [MotionSpec.dockPulseMs] after
  /// [startMs]; `0` before and after.
  static double pulse(double tMs, double startMs, MotionSpec spec) {
    final u = (tMs - startMs) / spec.dockPulseMs;
    if (spec.reducedMotion || u < 0 || u >= 1) {
      return 0;
    }
    return 1 - u;
  }
}
