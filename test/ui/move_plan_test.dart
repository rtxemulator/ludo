import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/fx_scene.dart';
import 'package:ludo/ui/core/move_plan.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

MoveAnimationPlan planFor(GameState before, int tokenIndex,
    {MotionSpec spec = MotionSpec.standard}) {
  final move = Engine.legalMoves(before).singleWhere(
    (m) => m.tokenIndex == tokenIndex,
  );
  final after = Engine.apply(before, move);
  return MoveAnimationPlan.plan(
      before: before, after: after, move: move, spec: spec);
}

void main() {
  const geo = BoardGeometry();

  test('plain move: one animated token, no victims, no ring', () {
    final before = makeState(tokens: {
      0: [2, -1, -1, -1],
    }, dice: 3);
    final plan = planFor(before, 0);
    expect(plan.victims, isEmpty);
    expect(plan.ring, isNull);
    expect(plan.mover.durationMs, 3 * 130 + 100);
    expect(plan.totalMs, plan.mover.durationMs);
    expect(plan.poseOf(0, 0, 0)!.pos, geo.trackCell(2));
    expect(plan.poseOf(0, 0, plan.totalMs)!.pos, geo.trackCell(5));
    expect(plan.poseOf(0, 1, 100), isNull);
    expect(plan.poseOf(1, 0, 100), isNull);
  });

  test('forming a blockade throws wall rings and a glow from its square', () {
    const rules = RulesConfig(blockades: true);
    final before = makeState(
      rules: rules,
      tokens: {
        0: [0, 0, -1, -1],
      },
      dice: 4,
    );
    final move = Engine.legalMoves(before).singleWhere((m) => m.isUnit);
    final after = Engine.apply(before, move);
    final plan = MoveAnimationPlan.plan(
      before: before,
      after: after,
      move: move,
    );
    expect(plan.formed, isTrue);
    expect(plan.partner, isNotNull);
    final walls = plan.effects.rings.where((r) => r.kind == FxKind.wall);
    expect(walls, hasLength(2));
    expect(walls.first.seat, 0);
    expect(plan.effects.glows, isNotEmpty);
  });

  test('a plain move, or one that does not make a pair, forms nothing', () {
    const rules = RulesConfig(blockades: true);
    final plain = makeState(
      rules: rules,
      tokens: {
        0: [2, -1, -1, -1],
      },
      dice: 3,
    );
    expect(planFor(plain, 0).formed, isFalse);
    // Splitting a pair by moving one token forms no blockade either.
    final pair = makeState(
      rules: rules,
      tokens: {
        0: [10, 10, -1, -1],
      },
      dice: 3,
    );
    final plan = planFor(pair, 0);
    expect(plan.formed, isFalse);
    expect(plan.effects.rings.where((r) => r.kind == FxKind.wall), isEmpty);
  });

  test('moving onto a token of your own forms a blockade', () {
    const rules = RulesConfig(blockades: true);
    final before = makeState(
      rules: rules,
      tokens: {
        0: [10, 7, -1, -1],
      },
      dice: 3,
    );
    final plan = planFor(before, 1);
    expect(plan.formed, isTrue);
  });

  test('yard exit uses the single exit hop from the yard spot', () {
    final before = makeState(dice: 6);
    final plan = planFor(before, 0);
    expect(plan.mover.durationMs, 220 + 100);
    expect(plan.poseOf(0, 0, 0)!.pos, geo.yardSpot(0, 0));
    expect(plan.poseOf(0, 0, plan.totalMs)!.pos, geo.trackCell(0));
  });

  test('capture: victim waits for the impact, then shakes and flies home', () {
    // Seat 0 token lands on abs 5 (not a safe square) where seat 1 sits.
    final before = makeState(tokens: {
      0: [2, -1, -1, -1],
      1: [relativeFor(1, 5), -1, -1, -1],
    }, dice: 3);
    final plan = planFor(before, 0);
    expect(plan.victims, hasLength(1));
    final victim = plan.victims.single;
    expect((victim.seat, victim.tokenIndex), (1, 0));
    expect(victim.delayMs, plan.mover.impactMs);
    expect(plan.totalMs, victim.delayMs + victim.timeline.durationMs);
    // Before the impact the victim is still on its square, untouched.
    expect(plan.poseOf(1, 0, 0)!.pos, geo.trackCell(5));
    expect(plan.poseOf(1, 0, victim.delayMs - 1)!.pos, geo.trackCell(5));
    // At the end it is back in its yard.
    expect(plan.poseOf(1, 0, plan.totalMs)!.pos, geo.yardSpot(1, 0));
  });

  test('landing on a safe square captures nothing and plans no victim', () {
    // Abs 8 is a star square; seat 1 sits there (relative 47).
    final before = makeState(tokens: {
      0: [3, -1, -1, -1],
      1: [relativeFor(1, 8), -1, -1, -1],
    }, dice: 5);
    final plan = planFor(before, 0);
    expect(plan.victims, isEmpty);
    // The mover ends beside (not on top of) the other token.
    final moverEnd = plan.poseOf(0, 0, plan.totalMs)!.pos;
    expect(moverEnd.distanceTo(geo.trackCell(8)), lessThan(0.5));
    expect(moverEnd, isNot(geo.trackCell(8)));
  });

  test('reaching home plans a ring and a pocket landing', () {
    final before = makeState(tokens: {
      0: [53, -1, -1, -1],
    }, dice: 3);
    final plan = planFor(before, 0);
    expect(plan.ring, isNotNull);
    expect(plan.ring!.startMs, plan.mover.impactMs);
    expect(plan.totalMs, greaterThanOrEqualTo(plan.ring!.endMs));
    expect(plan.poseOf(0, 0, plan.totalMs)!.pos, geo.finishSlot(0, 0));
    final path = [
      geo.homeCell(0, 54),
      geo.homeCell(0, 55),
    ];
    // Passes through the home column cells on the way.
    expect(plan.poseOf(0, 0, 130)!.pos.distanceTo(path[0]), lessThan(1e-9));
    expect(plan.poseOf(0, 0, 260)!.pos.distanceTo(path[1]), lessThan(1e-9));
  });

  test('moves along the track pass through every intermediate square', () {
    final before = makeState(tokens: {
      1: [10, -1, -1, -1],
    }, currentSeat: 1, dice: 4);
    final plan = planFor(before, 0);
    for (var step = 0; step <= 4; step++) {
      final pos = plan.poseOf(1, 0, step * 130.0)!.pos;
      expect(pos.distanceTo(geo.trackCell(absoluteSquare(1, 10 + step))),
          lessThan(1e-9),
          reason: 'step $step');
    }
  });

  test('reduced motion: no ring, shorter total, same endpoints', () {
    final before = makeState(tokens: {
      0: [53, -1, -1, -1],
    }, dice: 3);
    final plan = planFor(before, 0, spec: MotionSpec.reduced);
    expect(plan.totalMs, 240);
    expect(plan.poseOf(0, 0, plan.totalMs)!.pos, geo.finishSlot(0, 0));
  });

  test('works on a full random game: every applied move yields a valid plan',
      () {
    var state = Engine.newGame(seed: 12345);
    var plans = 0;
    for (var i = 0; i < 400 && !state.isOver; i++) {
      state = Engine.nextDecision(state);
      if (state.isOver) {
        break;
      }
      final moves = Engine.legalMoves(state);
      final move = moves[i % moves.length];
      final after = Engine.apply(state, move);
      final plan =
          MoveAnimationPlan.plan(before: state, after: after, move: move);
      expect(plan.totalMs, greaterThan(0));
      final end = plan.poseOf(move.owner, move.tokenIndex, plan.totalMs)!;
      final rest = geo.restingPoints(after)[move.owner][move.tokenIndex];
      expect(end.pos.distanceTo(rest), lessThan(1e-9));
      for (final v in plan.victims) {
        expect(
            plan
                .poseOf(v.seat, v.tokenIndex, plan.totalMs)!
                .pos
                .distanceTo(geo.restingPoints(after)[v.seat][v.tokenIndex]),
            lessThan(1e-9));
      }
      plans++;
      state = after;
    }
    expect(plans, greaterThan(50));
  });
}
