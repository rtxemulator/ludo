/// The effects that are alive on the board right now (rings, sparks, pocket
/// glow, tap nudges), with absolute start times so they outlive the move plan
/// that spawned them. Pure Dart, no Flutter.
library;

import 'fx.dart';
import 'motion_spec.dart';
import 'pt.dart';

/// What a ring means (the painter picks a colour and a stroke from it).
enum FxKind { dust, shockwave, yardExit, ripple, nudge }

/// A ring effect and the seat whose colour it wears.
class FxRing {
  const FxRing({required this.ring, required this.seat, required this.kind});

  final RingFx ring;
  final int seat;
  final FxKind kind;
}

/// Sparks of one token that reached home.
class FxSparks {
  const FxSparks({required this.burst, required this.seat});

  final SparkBurst burst;
  final int seat;
}

/// Glow of a finish pocket after a token settled in it.
class FxGlow {
  const FxGlow({
    required this.center,
    required this.seat,
    required this.startMs,
    this.spec = MotionSpec.standard,
  });

  final Pt center;
  final int seat;
  final double startMs;
  final MotionSpec spec;

  double get endMs => startMs + spec.pocketGlowMs;

  /// `0..1..0` strength at global time [tMs].
  double sample(double tMs) => pocketGlow(tMs, startMs, spec);
}

/// A token that was tapped but cannot move.
class FxNudge {
  const FxNudge({
    required this.seat,
    required this.index,
    required this.startMs,
  });

  final int seat;
  final int index;
  final double startMs;
}

/// Effects spawned by one move (absolute times).
class PlanEffects {
  const PlanEffects({
    this.rings = const [],
    this.sparks = const [],
    this.glows = const [],
  });

  final List<FxRing> rings;
  final List<FxSparks> sparks;
  final List<FxGlow> glows;
}

/// Everything alive now. The controller feeds it and prunes it every frame.
class FxScene {
  final List<FxRing> rings = [];
  final List<FxSparks> sparks = [];
  final List<FxGlow> glows = [];
  final List<FxNudge> nudges = [];

  void addAll(PlanEffects effects) {
    rings.addAll(effects.rings);
    sparks.addAll(effects.sparks);
    glows.addAll(effects.glows);
  }

  void addNudge(FxNudge nudge, Pt center, MotionSpec spec) {
    nudges.add(nudge);
    rings.add(
      FxRing(
        ring: RingFx.nudge(
          center: center,
          startMs: nudge.startMs,
          spec: spec,
        ),
        seat: nudge.seat,
        kind: FxKind.nudge,
      ),
    );
  }

  /// Sideways offset (cells) of token ([seat], [index]) at [tMs].
  double nudgeOf(int seat, int index, double tMs, MotionSpec spec) {
    var dx = 0.0;
    for (final n in nudges) {
      if (n.seat == seat && n.index == index) {
        dx += nudgeOffset(tMs, n.startMs, spec);
      }
    }
    return dx;
  }

  /// Drops what has finished by [nowMs].
  void prune(double nowMs, MotionSpec spec) {
    rings.removeWhere((r) => r.ring.endMs <= nowMs);
    sparks.removeWhere((s) => s.burst.endMs <= nowMs);
    glows.removeWhere((g) => g.endMs <= nowMs);
    nudges.removeWhere((n) => n.startMs + spec.nudgeMs <= nowMs);
  }

  void clear() {
    rings.clear();
    sparks.clear();
    glows.clear();
    nudges.clear();
  }

  bool get isEmpty =>
      rings.isEmpty && sparks.isEmpty && glows.isEmpty && nudges.isEmpty;

  /// Upper bound of the particles that exist now (sparks only; rings and
  /// glows are single shapes).
  int get particleCount =>
      sparks.fold(0, (n, s) => n + s.burst.spec.sparkCount);
}
