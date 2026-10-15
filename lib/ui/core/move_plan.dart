/// Turns an engine transition (`before -> after`) into an animation plan.
///
/// The plan only *presents* what the engine already decided; it never
/// mutates or recomputes game state.
library;

import 'package:ludo/engine/ludo_engine.dart';

import 'board_geometry.dart';
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
    required this.mover,
    required this.victims,
    required this.ring,
    required this.totalMs,
  });

  /// Plans the animation of [move] taking [before] to [after].
  factory MoveAnimationPlan.plan({
    required GameState before,
    required GameState after,
    required Move move,
    BoardGeometry geometry = const BoardGeometry(),
    MotionSpec spec = MotionSpec.standard,
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
    final mover = TokenTimeline.hop(
      path: path,
      fromYard: from == yardPosition,
      toFinish: reachedHome,
      spec: spec,
    );

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
      mover: mover,
      victims: victims,
      ring: ring,
      totalMs: total,
    );
  }

  final int owner;
  final int tokenIndex;
  final TokenTimeline mover;
  final List<VictimAnimation> victims;

  /// Present only when the move finished a token.
  final RingBurst? ring;

  /// When input may be unlocked again.
  final double totalMs;

  /// Pose of token ([seat], [index]) at global time [tMs], or `null` when the
  /// plan does not animate it (draw it at its resting point).
  TokenPose? poseOf(int seat, int index, double tMs) {
    if (seat == owner && index == tokenIndex) {
      return mover.sample(tMs);
    }
    for (final v in victims) {
      if (v.seat == seat && v.tokenIndex == index) {
        return v.timeline.sample(tMs - v.delayMs);
      }
    }
    return null;
  }
}
