/// 3D tumbling die as pure math. No Flutter.
///
/// The painter draws a cube from [Dice3dTimeline.sample] and [visibleFaces];
/// everything that decides *what* is shown lives here and is unit tested.
/// Docs: docs/ludo-ui-ux.md section 4.2.
///
/// Dock-local frame of the offsets: origin = die resting spot (dock centre),
/// `+y` = toward the player's own edge (where the "hand" is), `-y` = toward
/// the board. The painter rotates this frame to the seat (section 3).
library;

import 'dart:math' as math;

import 'curves.dart';
import 'motion_spec.dart';
import 'pt.dart';
import 'rot3.dart';
import 'seeded.dart';

/// One face of the cube in the die's own frame.
///
/// [u] x [v] = [normal]; pips are laid out in the (u, v) plane.
class DieFace {
  const DieFace(this.value, this.normal, this.u, this.v);

  final int value;
  final Vec3 normal;
  final Vec3 u;
  final Vec3 v;
}

/// Standard die: opposite faces sum to 7 (1/6, 2/5, 3/4).
const List<DieFace> dieFaces = [
  DieFace(1, Vec3(0, 0, 1), Vec3(1, 0, 0), Vec3(0, 1, 0)),
  DieFace(6, Vec3(0, 0, -1), Vec3(0, 1, 0), Vec3(1, 0, 0)),
  DieFace(2, Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)),
  DieFace(5, Vec3(-1, 0, 0), Vec3(0, 0, 1), Vec3(0, 1, 0)),
  DieFace(3, Vec3(0, 1, 0), Vec3(0, 0, 1), Vec3(1, 0, 0)),
  DieFace(4, Vec3(0, -1, 0), Vec3(1, 0, 0), Vec3(0, 0, 1)),
];

/// Pip centres of [value] in face units (the face spans `-0.5..0.5`).
List<Pt> pipLayout(int value) {
  const a = 0.25;
  const tl = Pt(-a, -a);
  const tr = Pt(a, -a);
  const bl = Pt(-a, a);
  const br = Pt(a, a);
  const ml = Pt(-a, 0);
  const mr = Pt(a, 0);
  const c = Pt.zero;
  switch (value) {
    case 1:
      return const [c];
    case 2:
      return const [tl, br];
    case 3:
      return const [tl, c, br];
    case 4:
      return const [tl, tr, bl, br];
    case 5:
      return const [tl, tr, c, bl, br];
    case 6:
      return const [tl, tr, ml, mr, bl, br];
  }
  throw ArgumentError.value(value, 'value', 'a die face is 1..6');
}

/// Orientation that puts face [value] on top (toward the viewer, `+z`),
/// turned by [yaw] radians about the vertical axis.
Mat3 finalOrientation(int value, {double yaw = 0}) {
  final Mat3 base;
  switch (value) {
    case 1:
      base = Mat3.identity;
    case 6:
      base = Mat3.rotationX(math.pi);
    case 2:
      base = Mat3.rotationY(-math.pi / 2);
    case 5:
      base = Mat3.rotationY(math.pi / 2);
    case 3:
      base = Mat3.rotationX(math.pi / 2);
    case 4:
      base = Mat3.rotationX(-math.pi / 2);
    default:
      throw ArgumentError.value(value, 'value', 'a die face is 1..6');
  }
  return Mat3.rotationZ(yaw) * base;
}

/// A face that is turned toward the viewer, ready to draw.
///
/// A face-local point `(a, b)` (face units, `-0.5..0.5`) lands on the
/// screen at `(cx + ux a + vx b, cy + uy a + vy b)` in units of the cube
/// edge, measured from the cube centre (orthographic projection).
class FaceView {
  const FaceView({
    required this.value,
    required this.normalZ,
    required this.shade,
    required this.cx,
    required this.cy,
    required this.ux,
    required this.uy,
    required this.vx,
    required this.vy,
  });

  final int value;

  /// How directly the face looks at the viewer (`0..1`).
  final double normalZ;

  /// Brightness `0..1` under the overhead light (`ambient + diffuse x z`).
  final double shade;

  final double cx;
  final double cy;
  final double ux;
  final double uy;
  final double vx;
  final double vy;
}

/// Brightness of a face looking straight up.
const double _ambient = 0.55;

/// Faces turned toward the viewer under [rotation], far to near (draw in
/// this order). At most three; the overhead light is straight above, so the
/// shade depends only on how much a face looks up.
List<FaceView> visibleFaces(Mat3 rotation) {
  final out = <FaceView>[];
  for (final face in dieFaces) {
    final n = rotation.apply(face.normal);
    if (n.z <= 1e-6) {
      continue;
    }
    final u = rotation.apply(face.u);
    final v = rotation.apply(face.v);
    out.add(
      FaceView(
        value: face.value,
        normalZ: n.z,
        shade: _ambient + (1 - _ambient) * n.z,
        cx: n.x * 0.5,
        cy: n.y * 0.5,
        ux: u.x,
        uy: u.y,
        vx: v.x,
        vy: v.y,
      ),
    );
  }
  out.sort((a, b) => a.normalZ.compareTo(b.normalZ));
  return out;
}

/// What the die looks like at one instant.
class Dice3dPose {
  const Dice3dPose({
    required this.rotation,
    required this.offset,
    required this.height,
    required this.scale,
    required this.opacity,
    required this.shadowScale,
    required this.shadowOpacity,
    required this.ringRadius,
    required this.ringOpacity,
    required this.goldOpacity,
  });

  /// Orientation of the cube.
  final Mat3 rotation;

  /// Ground position relative to the dock centre, in cells (dock-local
  /// frame, see the library comment).
  final Pt offset;

  /// Height above the table in cells (`>= 0`). Never turned into a Y
  /// offset: it is already folded into [scale].
  final double height;

  /// Total uniform scale: pop-in x height x impact press.
  final double scale;
  final double opacity;

  /// Shadow size relative to the die footprint (widens with height).
  final double shadowScale;

  /// Shadow strength `0..1` (fades with height).
  final double shadowOpacity;

  /// Result ring in cells (0 radius and opacity outside the reveal).
  final double ringRadius;
  final double ringOpacity;

  /// Gold halo for a six (bonus turn), `0..1`; always 0 for other values.
  final double goldOpacity;
}

/// One roll of the 3D die.
///
/// The outcome [value] is decided by the engine. The orientation is
/// `R(t) = Rz(wobble) * R_final(value) * Rot(A, a(t)) * Rot(B, b(t))` where
/// `a, b -> 0` with `easeOutCubic`, so the rolled face is on top at the end
/// by construction and nothing about the result is stored in the tumble.
class Dice3dTimeline {
  Dice3dTimeline({
    required this.value,
    required this.seed,
    this.spec = MotionSpec.standard,
  }) : assert(value >= 1 && value <= 6) {
    final d = spec.dice3d;
    final rnd = Seeded(seed ^ (value * 0x9E3779B1));
    yaw = rnd.spread(d.maxYawDegrees * math.pi / 180);
    _axisA = _randomAxis(rnd);
    _axisB = _randomAxis(rnd);
    _totalA =
        _signed(rnd, d.tumbleTurnsA * 2 * math.pi * rnd.range(0.85, 1.15));
    _totalB =
        _signed(rnd, d.tumbleTurnsB * 2 * math.pi * rnd.range(0.85, 1.15));
    landing = Pt(rnd.spread(d.landingJitter), rnd.spread(d.landingJitter));
    _hand = Pt(rnd.spread(0.6), d.handDistance);
    finalRotation = finalOrientation(value, yaw: yaw);
  }

  static Vec3 _randomAxis(Seeded rnd) {
    final z = rnd.range(-1, 1);
    final phi = rnd.range(0, 2 * math.pi);
    final r = math.sqrt(1 - z * z);
    return Vec3(r * math.cos(phi), r * math.sin(phi), z);
  }

  static double _signed(Seeded rnd, double v) => rnd.next() < 0.5 ? -v : v;

  final int value;
  final int seed;
  final MotionSpec spec;

  /// Final rotation about the vertical axis, radians.
  late final double yaw;

  /// Where the die comes to rest relative to the dock centre (cells).
  late final Pt landing;

  /// Orientation at rest.
  late final Mat3 finalRotation;

  late final Vec3 _axisA;
  late final Vec3 _axisB;
  late final double _totalA;
  late final double _totalB;
  late final Pt _hand;

  /// Total length including the reveal.
  double get durationMs =>
      spec.reducedMotion ? spec.reducedFadeMs : spec.dice3d.revealEndMs;

  /// When the face locks (the result may be acted on).
  double get settleMs =>
      spec.reducedMotion ? spec.reducedFadeMs : spec.dice3d.settleEndMs;

  /// Moments the die hits the table (empty in reduced motion).
  List<double> get impactsMs =>
      spec.reducedMotion ? const [] : spec.dice3d.impactsMs;

  Dice3dPose sample(double tMs) {
    final d = spec.dice3d;
    final t = tMs < 0 ? 0.0 : (tMs > durationMs ? durationMs : tMs);
    if (spec.reducedMotion) {
      return Dice3dPose(
        rotation: finalRotation,
        offset: landing,
        height: 0,
        scale: 1,
        opacity: clamp01(t / spec.reducedFadeMs),
        shadowScale: 1,
        shadowOpacity: 1,
        ringRadius: 0,
        ringOpacity: 0,
        goldOpacity: 0,
      );
    }

    // Height (cells): three arcs with decaying apex.
    double h = 0;
    if (t >= d.popInMs && t < d.flightEndMs) {
      h = arc((t - d.popInMs) / (d.flightEndMs - d.popInMs), d.flightApex);
    } else if (t >= d.flightEndMs && t < d.bounce2EndMs) {
      h = arc((t - d.flightEndMs) / (d.bounce2EndMs - d.flightEndMs),
          d.bounce2Apex);
    } else if (t >= d.bounce2EndMs && t < d.bounce3EndMs) {
      h = arc((t - d.bounce2EndMs) / (d.bounce3EndMs - d.bounce2EndMs),
          d.bounce3Apex);
    }

    // Horizontal progress from the hand to the landing spot.
    final p = _progress(t, d);
    final offset = Pt.lerp(_hand, landing, p);

    // Orientation.
    final w = clamp01(t / d.bounce3EndMs);
    final k = 1 - easeOutCubic(w);
    var rotation = finalRotation *
        Mat3.axisAngle(_axisA, _totalA * k) *
        Mat3.axisAngle(_axisB, _totalB * k);
    if (t >= d.bounce3EndMs) {
      final s =
          clamp01((t - d.bounce3EndMs) / (d.settleEndMs - d.bounce3EndMs));
      final wobble = d.wobbleDegrees *
          math.pi /
          180 *
          dampedSine(s, cycles: d.wobbleCycles, decay: d.wobbleDecay);
      rotation = Mat3.rotationZ(wobble) * rotation;
    }

    // Scale: pop-in, height, impact press.
    final scale = _pop(t, d) * (1 + d.liftScalePerCell * h) * _press(t, d);

    // Reveal ring and six halo.
    var ringRadius = 0.0;
    var ringOpacity = 0.0;
    var gold = 0.0;
    if (t >= d.settleEndMs) {
      final u = clamp01((t - d.settleEndMs) / (d.revealEndMs - d.settleEndMs));
      if (u < 1) {
        final e = easeOutCubic(u);
        ringRadius = d.dieCells * (0.65 + 0.55 * e);
        ringOpacity = 0.7 * (1 - e);
        if (value == 6) {
          gold = math.sin(math.pi * u);
        }
      }
    }

    return Dice3dPose(
      rotation: rotation,
      offset: offset,
      height: h,
      scale: scale,
      opacity: clamp01(t / 60),
      shadowScale: 1 + 0.6 * h,
      shadowOpacity: 1 / (1 + 1.2 * h),
      ringRadius: ringRadius,
      ringOpacity: ringOpacity,
      goldOpacity: gold,
    );
  }

  /// Fraction of the way from the hand to the landing spot.
  static double _progress(double t, Dice3dSpec d) {
    final knots = <(double, double)>[
      (0, 0),
      (d.popInMs, 0),
      (d.flightEndMs, 0.72),
      (d.bounce2EndMs, 0.93),
      (d.bounce3EndMs, 0.99),
    ];
    if (t >= d.bounce3EndMs) {
      final s =
          clamp01((t - d.bounce3EndMs) / (d.settleEndMs - d.bounce3EndMs));
      return 0.99 + 0.01 * easeOutCubic(s);
    }
    for (var i = 0; i < knots.length - 1; i++) {
      final (t0, p0) = knots[i];
      final (t1, p1) = knots[i + 1];
      if (t < t1) {
        return p0 + (p1 - p0) * (t1 == t0 ? 1 : (t - t0) / (t1 - t0));
      }
    }
    return 0.99;
  }

  /// 0.6 -> 1.1 -> 1 over the pop-in, then 1.
  static double _pop(double t, Dice3dSpec d) {
    if (t >= d.popInMs) {
      return 1;
    }
    final u = t / d.popInMs;
    if (u < 0.6) {
      return d.popFromScale + (1.1 - d.popFromScale) * easeOutCubic(u / 0.6);
    }
    return 1.1 - 0.1 * easeInOutSine((u - 0.6) / 0.4);
  }

  /// Uniform press 1 -> pressScale -> 1 at each impact.
  static double _press(double t, Dice3dSpec d) {
    for (final impact in d.impactsMs) {
      if (t >= impact && t < impact + d.pressMs) {
        return 1 -
            (1 - d.pressScale) * math.sin(math.pi * (t - impact) / d.pressMs);
      }
    }
    return 1;
  }
}
