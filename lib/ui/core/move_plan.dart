/// Turns an engine transition (`before -> after`) into an animation plan.
///
/// The plan only *presents* what the engine already decided; it never
/// mutates or recomputes game state.
library;

import 'package:ludo/engine/ludo_engine.dart';

import 'board_geometry.dart';
import 'fx.dart';
import 'fx_scene.dart';
import 'motion_spec.dart';
import 'pt.dart';
import 'token_timeline.dart';

/// A captured token and when its animation starts.
class VictimAnimation {
  const VictimAnimation({
    required this.seat,
    required this.tokenIndex,
    required this.delayMs,
    required this.timeline,
  });

  final int seat;
  final int tokenIndex;
  final double delayMs;
  final TokenTimeline timeline;
}

/// Everything the painter needs to animate one applied move.
class MoveAnimationPlan {
  const MoveAnimationPlan._({
    required this.owner,
    required this.tokenIndex,
    required this.partnerIndex,
    required this.formed,
    required this.mover,
    required this.partner,
    required this.victims,
    required this.ring,
    required this.effects,
    required this.totalMs,
  });

  /// Plans the animation of [move] taking [before] to [after]. [startMs] is
  /// the global time the plan starts at: the token timelines stay relative,
  /// the [effects] carry absolute times.
  factory MoveAnimationPlan.plan({
    required GameState before,
    required GameState after,
    required Move move,
    BoardGeometry geometry = const BoardGeometry(),
    MotionSpec spec = MotionSpec.standard,
    double startMs = 0,
  }) {
    final owner = move.owner;
    final index = move.tokenIndex;
    final from = before.tokens[owner][index];
    final to = after.tokens[owner][index];
    final restBefore = geometry.restingPoints(before);
    final restAfter = geometry.restingPoints(after);

    final path = <Pt>[restBefore[owner][index]];
    if (from == yardPosition) {
      path.add(restAfter[owner][index]);
    } else {
      for (var p = from + 1; p < to; p++) {
        path.add(geometry.cellCenter(owner, p, index));
      }
      path.add(restAfter[owner][index]);
    }
    final reachedHome = to == finishPosition;
    final formed = isOnTrack(to) &&
        _holdsBlockade(after, owner, to) &&
        !_holdsBlockade(before, owner, to);
    final mover = TokenTimeline.hop(
      path: path,
      fromYard: from == yardPosition,
      toFinish: reachedHome,
      spec: spec,
    );
    // A moving blockade carries its partner along the same way.
    TokenTimeline? partner;
    if (move.isUnit) {
      final other = move.partnerIndex;
      final partnerPath = <Pt>[restBefore[owner][other]];
      for (var p = from + 1; p < to; p++) {
        partnerPath.add(geometry.cellCenter(owner, p, other));
      }
      partnerPath.add(restAfter[owner][other]);
      partner = TokenTimeline.hop(
        path: partnerPath,
        fromYard: false,
        toFinish: false,
        spec: spec,
      );
    }

    final victims = <VictimAnimation>[];
    for (var seat = 0; seat < seatCount; seat++) {
      if (seat == owner) {
        continue;
      }
      for (var i = 0; i < tokensPerSeat; i++) {
        final was = before.tokens[seat][i];
        if (isOnTrack(was) && after.tokens[seat][i] == yardPosition) {
          victims.add(
            VictimAnimation(
              seat: seat,
              tokenIndex: i,
              delayMs: mover.impactMs,
              timeline: TokenTimeline.captured(
                square: restBefore[seat][i],
                yard: restAfter[seat][i],
                spec: spec,
              ),
            ),
          );
        }
      }
    }

    final ring = reachedHome
        ? RingBurst(
            center: restAfter[owner][index],
            startMs: mover.impactMs,
            spec: spec,
          )
        : null;

    final effects = _effects(
      before: before,
      move: move,
      geometry: geometry,
      spec: spec,
      startMs: startMs,
      mover: mover,
      victims: victims,
      restBefore: restBefore,
      restAfter: restAfter,
      fromYard: from == yardPosition,
      reachedHome: reachedHome,
      formed: formed,
    );

    var total = mover.durationMs;
    for (final v in victims) {
      total = total > v.delayMs + v.timeline.durationMs
          ? total
          : v.delayMs + v.timeline.durationMs;
    }
    if (ring != null && ring.endMs > total && !spec.reducedMotion) {
      total = ring.endMs;
    }

    return MoveAnimationPlan._(
      owner: owner,
      tokenIndex: index,
      partnerIndex: move.partnerIndex,
      formed: formed,
      mover: mover,
      partner: partner,
      victims: victims,
      ring: ring,
      effects: effects,
      totalMs: total,
    );
  }

  final int owner;
  final int tokenIndex;

  /// The second token of a moving blockade, or `-1`.
  final int partnerIndex;

  /// Whether this move formed a blockade (a new pair on an ordinary square).
  final bool formed;
  final TokenTimeline mover;

  /// The timeline of the partner token (moving blockades only).
  final TokenTimeline? partner;
  final List<VictimAnimation> victims;

  /// Present only when the move finished a token.
  final RingBurst? ring;

  /// Rings, sparks and glows this move spawns (absolute times); they live on
  /// in the controller's scene after the plan ends.
  final PlanEffects effects;

  /// When input may be unlocked again.
  final double totalMs;

  /// Pose of token ([seat], [index]) at global time [tMs], or `null` when the
  /// plan does not animate it (draw it at its resting point).
  TokenPose? poseOf(int seat, int index, double tMs) {
    if (seat == owner && index == tokenIndex) {
      return mover.sample(tMs);
    }
    if (seat == owner && index == partnerIndex && partner != null) {
      return partner!.sample(tMs);
    }
    for (final v in victims) {
      if (v.seat == seat && v.tokenIndex == index) {
        return v.timeline.sample(tMs - v.delayMs);
      }
    }
    return null;
  }
}

PlanEffects _effects({
  required GameState before,
  required Move move,
  required BoardGeometry geometry,
  required MotionSpec spec,
  required double startMs,
  required TokenTimeline mover,
  required List<VictimAnimation> victims,
  required List<List<Pt>> restBefore,
  required List<List<Pt>> restAfter,
  required bool fromYard,
  required bool reachedHome,
  required bool formed,
}) {
  final owner = move.owner;
  final index = move.tokenIndex;
  final impact = startMs + mover.impactMs;
  final land = restAfter[owner][index];
  final rings = <FxRing>[];
  final sparks = <FxSparks>[];
  final glows = <FxGlow>[];

  if (fromYard) {
    rings.add(
      FxRing(
        ring: RingFx.yardExit(
          center: restBefore[owner][index],
          startMs: startMs,
          spec: spec,
        ),
        seat: owner,
        kind: FxKind.yardExit,
      ),
    );
  }

  if (victims.isNotEmpty) {
    for (final v in victims) {
      rings.add(
        FxRing(
          ring: RingFx.shockwave(
            center: restBefore[v.seat][v.tokenIndex],
            startMs: startMs + v.delayMs,
            spec: spec,
          ),
          seat: owner,
          kind: FxKind.shockwave,
        ),
      );
      // The victim lands in its yard with a soft ring.
      rings.add(
        FxRing(
          ring: RingFx.dust(
            center: restAfter[v.seat][v.tokenIndex],
            startMs: startMs +
                v.delayMs +
                spec.captureShakeMs +
                spec.captureReturnMs,
            spec: spec,
          ),
          seat: v.seat,
          kind: FxKind.dust,
        ),
      );
    }
  } else if (reachedHome) {
    sparks.add(
      FxSparks(
        burst: SparkBurst(
          center: land,
          startMs: impact,
          seed: (before.turnNumber * 7919 + owner * 4 + index) & 0x7fffffff,
          spec: spec,
        ),
        seat: owner,
      ),
    );
    glows.add(FxGlow(center: land, seat: owner, startMs: impact, spec: spec));
  } else if (fromYard) {
    rings.add(
      FxRing(
        ring: RingFx.ripple(center: land, startMs: impact, spec: spec),
        seat: owner,
        kind: FxKind.ripple,
      ),
    );
  } else {
    rings.add(
      FxRing(
        ring: RingFx.dust(center: land, startMs: impact, spec: spec),
        seat: owner,
        kind: FxKind.dust,
      ),
    );
  }
  if (formed) {
    // A blockade went up: two rings and a glow in the owner's colour from the
    // square itself.
    final wall = geometry.trackCell(absoluteSquare(owner, move.to));
    for (final delay in const [0.0, 110.0]) {
      rings.add(
        FxRing(
          ring: RingFx.wall(center: wall, startMs: impact + delay, spec: spec),
          seat: owner,
          kind: FxKind.wall,
        ),
      );
    }
    glows.add(FxGlow(center: wall, seat: owner, startMs: impact, spec: spec));
  }
  if (move.isUnit) {
    rings.add(
      FxRing(
        ring: RingFx.dust(
          center: restAfter[owner][move.partnerIndex],
          startMs: impact,
          spec: spec,
        ),
        seat: owner,
        kind: FxKind.dust,
      ),
    );
  }
  return PlanEffects(rings: rings, sparks: sparks, glows: glows);
}

/// Whether [seat] holds a blockade on its relative track position [position].
bool _holdsBlockade(GameState state, int seat, int position) {
  final square = absoluteSquare(seat, position);
  return Engine.blockades(state)
      .any((b) => b.seat == seat && b.square == square);
}
