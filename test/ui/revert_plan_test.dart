import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/revert_plan.dart';
import 'package:ludo/ui/core/token_timeline.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

const _geo = BoardGeometry();
const _spec = MotionSpec.standard;
const _banked = RulesConfig(bankedRolls: true);

void main() {
  group('TokenTimeline.glide', () {
    const from = Pt(2, 2);
    const to = Pt(8, 5);
    final glide = TokenTimeline.glide(from: from, to: to);

    test('starts at the source and lands on the target', () {
      expect(glide.sample(0).pos.x, closeTo(from.x, 1e-9));
      expect(glide.sample(0).pos.y, closeTo(from.y, 1e-9));
      expect(glide.sample(glide.durationMs).pos.x, closeTo(to.x, 1e-9));
      expect(glide.sample(glide.durationMs).pos.y, closeTo(to.y, 1e-9));
      expect(glide.durationMs, _spec.revertMs + _spec.landSquashMs);
      expect(glide.impactMs, _spec.revertMs);
    });

    test('moves monotonically along the line and lifts mid-flight', () {
      var lastX = from.x - 1e-9;
      for (var t = 0.0; t <= _spec.revertMs; t += 10) {
        final p = glide.sample(t);
        expect(p.pos.x, greaterThanOrEqualTo(lastX));
        lastX = p.pos.x;
      }
      final mid = glide.sample(_spec.revertMs / 2);
      expect(mid.lift, closeTo(_spec.revertArc, 1e-9));
      expect(mid.scale, greaterThan(1));
      expect(glide.sample(0).lift, 0);
    });

    test('reduced motion cross-fades instead', () {
      final jump = TokenTimeline.glide(
        from: from,
        to: to,
        spec: MotionSpec.reduced,
      );
      expect(jump.durationMs, 2 * MotionSpec.reduced.reducedFadeMs);
      expect(jump.sample(0).opacity, 1);
      expect(jump.sample(jump.durationMs).pos.x, to.x);
      expect(jump.sample(jump.durationMs).opacity, 1);
    });
  });

  group('RevertAnimation', () {
    // Before: seat 0 advanced token 0 from 10 to 14 and captured seat 1's
    // token (absolute square 14). The revert puts both back.
    final before = makeState(
      rules: _banked,
      tokens: {
        0: [14, 20, -1, -1],
        1: [-1, -1, -1, -1],
      },
    );
    final after = makeState(
      rules: _banked,
      tokens: {
        0: [10, 20, -1, -1],
        1: [relativeFor(1, 14), -1, -1, -1],
      },
    );

    test('only the tokens that differ glide, back to their old cells', () {
      final plan = RevertAnimation.plan(before: before, after: after);
      expect(plan.isEmpty, isFalse);
      expect(plan.tokens, hasLength(2));
      final rb = _geo.restingPoints(before);
      final ra = _geo.restingPoints(after);

      final mover = plan.poseOf(0, 0, 0)!;
      expect(mover.pos.x, closeTo(rb[0][0].x, 1e-9));
      final end = plan.totalMs;
      expect(plan.poseOf(0, 0, end)!.pos.x, closeTo(ra[0][0].x, 1e-9));
      expect(plan.poseOf(1, 0, end)!.pos.y, closeTo(ra[1][0].y, 1e-9));

      // Tokens that did not change are not animated.
      expect(plan.poseOf(0, 1, 100), isNull);
      expect(plan.poseOf(2, 3, 100), isNull);
    });

    test('tokens start one stagger apart and the plan ends with the last', () {
      final plan = RevertAnimation.plan(before: before, after: after);
      final glide = _spec.revertMs + _spec.landSquashMs;
      expect(plan.totalMs, _spec.revertStaggerMs + glide);
      // The second token has not started at t = 0.
      final rb = _geo.restingPoints(before);
      expect(plan.poseOf(1, 0, 0)!.pos.x, closeTo(rb[1][0].x, 1e-9));
    });

    test('each landing leaves a dust ring at its cell', () {
      final plan = RevertAnimation.plan(
        before: before,
        after: after,
        startMs: 1000,
      );
      expect(plan.effects.rings, hasLength(2));
      for (final r in plan.effects.rings) {
        expect(r.ring.startMs, greaterThanOrEqualTo(1000 + _spec.revertMs));
      }
    });

    test('nothing differs: an empty plan that ends at once', () {
      final plan = RevertAnimation.plan(before: before, after: before);
      expect(plan.isEmpty, isTrue);
      expect(plan.totalMs, 0);
      expect(plan.poseOf(0, 0, 0), isNull);
    });
  });
}
