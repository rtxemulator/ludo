/// Easing and shaping functions. Pure Dart, no Flutter.
///
/// Every [Ease] maps progress `0..1` to eased progress and clamps its input.
library;

import 'dart:math' as math;

/// A function from linear progress `0..1` to eased progress.
typedef Ease = double Function(double t);

/// Clamps [v] to `0..1`.
double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

double linear(double t) => clamp01(t);

double easeOutCubic(double t) {
  final u = 1 - clamp01(t);
  return 1 - u * u * u;
}

double easeInCubic(double t) {
  final u = clamp01(t);
  return u * u * u;
}

double easeInOutCubic(double t) {
  final u = clamp01(t);
  if (u < 0.5) {
    return 4 * u * u * u;
  }
  final v = -2 * u + 2;
  return 1 - v * v * v / 2;
}

double easeInOutSine(double t) => 0.5 - 0.5 * math.cos(math.pi * clamp01(t));

/// Ease-out with overshoot (peaks above 1, then settles at exactly 1).
double easeOutBack(double t, {double overshoot = 1.70158}) {
  final u = clamp01(t) - 1;
  return 1 + (overshoot + 1) * u * u * u + overshoot * u * u;
}

/// CSS-style cubic bezier easing through `(0,0)`, `(x1,y1)`, `(x2,y2)`,
/// `(1,1)`.
Ease cubicBezier(double x1, double y1, double x2, double y2) {
  double bx(double s) {
    final m = 1 - s;
    return 3 * m * m * s * x1 + 3 * m * s * s * x2 + s * s * s;
  }

  double by(double s) {
    final m = 1 - s;
    return 3 * m * m * s * y1 + 3 * m * s * s * y2 + s * s * s;
  }

  double dbx(double s) {
    final m = 1 - s;
    return 3 * m * m * x1 + 6 * m * s * (x2 - x1) + 3 * s * s * (1 - x2);
  }

  return (double t) {
    final x = clamp01(t);
    if (x == 0 || x == 1) {
      return x;
    }
    var s = x;
    for (var i = 0; i < 8; i++) {
      final err = bx(s) - x;
      if (err.abs() < 1e-7) {
        return by(s);
      }
      final d = dbx(s);
      if (d.abs() < 1e-6) {
        break;
      }
      s -= err / d;
    }
    var lo = 0.0;
    var hi = 1.0;
    s = x;
    for (var i = 0; i < 40; i++) {
      final v = bx(s);
      if ((v - x).abs() < 1e-7) {
        break;
      }
      if (v < x) {
        lo = s;
      } else {
        hi = s;
      }
      s = (lo + hi) / 2;
    }
    return by(s);
  };
}

/// Parabolic arc: `0` at `u = 0` and `u = 1`, [height] at `u = 0.5`.
double arc(double u, double height) {
  final c = clamp01(u);
  return 4 * height * c * (1 - c);
}

/// Exponentially damped sine wave. With an integer [cycles] it is exactly 0
/// at `u = 0` and `u = 1`, so segments join without a pop.
double dampedSine(double u, {required double cycles, required double decay}) {
  final c = clamp01(u);
  return math.exp(-decay * c) * math.sin(2 * math.pi * cycles * c);
}
