/// The banked-rolls "dead end" on the board: every token the turn moved
/// rewinds to where it was when the turn began, sliding back along the very
/// squares it had crossed (a token that left its yard goes back to the start
/// square and on into the yard; a captured token flies back to where it
/// stood). The engine has already reverted the state; this only *presents*
/// the difference between the state before the last roll and the state
/// after it. Pure Dart.
library;

import 'dart:math' as math;

import 'package:ludo/engine/ludo_engine.dart';

import 'board_geometry.dart';
import 'fx.dart';
import 'fx_scene.dart';
import 'motion_spec.dart';
import 'pt.dart';
import 'token_timeline.dart';

/// One token that goes back.
class RevertedToken {
  const RevertedToken({
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

/// Animation of a revert. Empty (no token differs) when the turn had not
/// moved anything yet; then [isEmpty] is true and [totalMs] is `0`.
class RevertAnimation {
  const RevertAnimation._({
    required this.tokens,
    required this.effects,
    required this.totalMs,
  });

  /// Plans the glide that takes [before] (the board when the dead-end roll
  /// was made) to [after] (the reverted board). [startMs] is the global time
  /// it starts at: the token timelines stay relative, the [effects] carry
  /// absolute times.
  factory RevertAnimation.plan({
    required GameState before,
    required GameState after,
    BoardGeometry geometry = const BoardGeometry(),
    MotionSpec spec = MotionSpec.standard,
    double startMs = 0,
  }) {
    final restBefore = geometry.restingPoints(before);
    final restAfter = geometry.restingPoints(after);
    final tokens = <RevertedToken>[];
    final rings = <FxRing>[];
    var total = 0.0;
    var n = 0;
    for (var seat = 0; seat < seatCount; seat++) {
      for (var i = 0; i < tokensPerSeat; i++) {
        if (before.tokens[seat][i] == after.tokens[seat][i]) {
          continue;
        }
        final delay = n * spec.revertStaggerMs;
        n++;
        final here = before.tokens[seat][i];
        final back = after.tokens[seat][i];
        final TokenTimeline timeline;
        if (here != yardPosition && back < here) {
          // Walked forward this turn: slide back over the same squares.
          final path = <Pt>[restBefore[seat][i]];
          for (var p = here - 1; p > math.max(back, 0); p--) {
            path.add(geometry.cellCenter(seat, p, i));
          }
          if (back == yardPosition && here > 0) {
            // Back to the start square first, then on into the yard.
            path.add(geometry.cellCenter(seat, 0, i));
          }
          path.add(restAfter[seat][i]);
          timeline = TokenTimeline.rewind(path: path, spec: spec);
        } else {
          // A captured token comes back from its yard: the flight home in
          // reverse.
          timeline = TokenTimeline.glide(
            from: restBefore[seat][i],
            to: restAfter[seat][i],
            spec: spec,
          );
        }
        tokens.add(
          RevertedToken(
            seat: seat,
            tokenIndex: i,
            delayMs: delay,
            timeline: timeline,
          ),
        );
        rings.add(
          FxRing(
            ring: RingFx.dust(
              center: restAfter[seat][i],
              startMs: startMs + delay + timeline.impactMs,
              spec: spec,
            ),
            seat: seat,
            kind: FxKind.dust,
          ),
        );
        final end = delay + timeline.durationMs;
        if (end > total) {
          total = end;
        }
      }
    }
    return RevertAnimation._(
      tokens: tokens,
      effects: PlanEffects(rings: rings),
      totalMs: total,
    );
  }

  final List<RevertedToken> tokens;
  final PlanEffects effects;

  /// When input may be unlocked again.
  final double totalMs;

  bool get isEmpty => tokens.isEmpty;

  /// Pose of token ([seat], [index]) at time [tMs] after the start, or
  /// `null` when it does not move (draw it at its resting point).
  TokenPose? poseOf(int seat, int index, double tMs) {
    for (final t in tokens) {
      if (t.seat == seat && t.tokenIndex == index) {
        return t.timeline.sample(tMs - t.delayMs);
      }
    }
    return null;
  }
}
