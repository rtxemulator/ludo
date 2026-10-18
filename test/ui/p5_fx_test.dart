import 'dart:math' as math;

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/frame_stats.dart';
import 'package:ludo/ui/core/fx.dart';
import 'package:ludo/ui/core/fx_scene.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/move_plan.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/token_timeline.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

MoveAnimationPlan planFor(
  GameState before,
  int tokenIndex, {
  MotionSpec spec = MotionSpec.standard,
  double startMs = 0,
}) {
  final move = Engine.legalMoves(before).singleWhere(
    (m) => m.tokenIndex == tokenIndex,
  );
  final after = Engine.apply(before, move);
  return MoveAnimationPlan.plan(
    before: before,
    after: after,
    move: move,
    spec: spec,
    startMs: startMs,
  );
}

Set<FxKind> kinds(MoveAnimationPlan plan) =>
    {for (final r in plan.effects.rings) r.kind};

void main() {
  const spec = MotionSpec.standard;
  const geo = BoardGeometry();

  group('captured token', () {
    final tl = TokenTimeline.captured(
      square: const Pt(6.5, 3.5),
      yard: const Pt(2, 2),
    );

    test('flips like a coin while flying: width 1 -> 0 (never 0) -> 1', () {
      expect(tl.sample(50).flipX, 1);
      var min = 1.0;
      for (var t = spec.captureShakeMs;
          t < spec.captureShakeMs + spec.captureReturnMs;
          t += 2) {
        final f = tl.sample(t).flipX;
        expect(f, inInclusiveRange(0.04, 1));
        min = math.min(min, f);
      }
      expect(min, lessThan(0.1));
      expect(tl.sample(tl.durationMs).flipX, 1);
    });

    test('lands with a uniform press that returns to 1', () {
      final land = spec.captureShakeMs + spec.captureReturnMs;
      final mid = tl.sample(land + spec.landSquashMs / 2);
      expect(mid.scale, closeTo(spec.pressScale, 1e-9));
      expect(mid.flipX, 1);
      expect(tl.sample(tl.durationMs).scale, closeTo(1, 1e-9));
    });
  });

  group('feedback curves', () {
    test('nudge: 0.07 amplitude, zero outside 160 ms and when reduced', () {
      var peak = 0.0;
      for (var t = 0.0; t < spec.nudgeMs; t++) {
        peak = math.max(peak, nudgeOffset(100 + t, 100, spec).abs());
      }
      expect(peak, greaterThan(0.03));
      expect(peak, lessThanOrEqualTo(spec.nudgeAmplitude));
      expect(nudgeOffset(99, 100, spec), 0);
      expect(nudgeOffset(100 + spec.nudgeMs, 100, spec), 0);
      expect(nudgeOffset(120, 100, MotionSpec.reduced), 0);
    });

    test('no-move dim is a 0..1..0 bump over 200 ms', () {
      expect(noMoveDim(0, 0, spec), closeTo(0, 1e-9));
      expect(noMoveDim(100, 0, spec), closeTo(1, 1e-9));
      expect(noMoveDim(200, 0, spec), 0);
      expect(noMoveDim(-1, 0, spec), 0);
      expect(noMoveDim(100, 0, MotionSpec.reduced), 0);
    });

    test('die shake stays inside its amplitude and ends at rest', () {
      var peak = 0.0;
      for (var t = 0.0; t < spec.dieShakeMs; t++) {
        peak = math.max(peak, dieShakeOffset(t, 0, spec).abs());
      }
      expect(peak, greaterThan(0.04));
      expect(peak, lessThanOrEqualTo(spec.dieShakeAmplitude));
      expect(dieShakeOffset(spec.dieShakeMs, 0, spec), 0);
    });

    test('toast fades in and out and lives 1.2 s', () {
      expect(toastLook(-1, 0, spec).opacity, 0);
      expect(toastLook(0, 0, spec).opacity, 0);
      expect(toastLook(600, 0, spec).opacity, 1);
      expect(toastLook(600, 0, spec).scale, closeTo(1, 1e-9));
      expect(toastLook(spec.toastMs - 90, 0, spec).opacity, closeTo(0.5, 1e-9));
      expect(toastLook(spec.toastMs, 0, spec).opacity, 0);
      expect(toastLook(600, 0, MotionSpec.reduced).scale, 1);
    });

    test('rank badge pops in and settles at 1', () {
      expect(rankBadgeScale(-5, 0, spec), 0);
      expect(rankBadgeScale(spec.rankBadgeMs, 0, spec), closeTo(1, 1e-9));
      var peak = 0.0;
      for (var t = 0.0; t <= spec.rankBadgeMs; t += 5) {
        peak = math.max(peak, rankBadgeScale(t, 0, spec));
      }
      expect(peak, greaterThan(1.0));
      expect(rankBadgeScale(10, 0, MotionSpec.reduced), 1);
    });
  });

  group('plan effects', () {
    test('plain move: one dust ring at the landing impact', () {
      final plan = planFor(
        makeState(tokens: {
          0: [2, -1, -1, -1],
        }, dice: 3),
        0,
        startMs: 1000,
      );
      expect(kinds(plan), {FxKind.dust});
      final ring = plan.effects.rings.single.ring;
      expect(ring.startMs, 1000 + plan.mover.impactMs);
      expect(ring.center, geo.trackCell(5));
      expect(plan.effects.sparks, isEmpty);
      expect(plan.effects.glows, isEmpty);
    });

    test('yard exit: contracting yard ring at the spot, ripple at the start',
        () {
      final plan = planFor(makeState(dice: 6), 0, startMs: 50);
      expect(kinds(plan), {FxKind.yardExit, FxKind.ripple});
      final exit =
          plan.effects.rings.firstWhere((r) => r.kind == FxKind.yardExit).ring;
      expect(exit.center, geo.yardSpot(0, 0));
      expect(exit.startMs, 50);
      expect(exit.startRadius, greaterThan(exit.endRadius));
      final ripple =
          plan.effects.rings.firstWhere((r) => r.kind == FxKind.ripple).ring;
      expect(ripple.center, geo.trackCell(0));
      expect(ripple.startMs, 50 + plan.mover.impactMs);
    });

    test('capture: shockwave on the victim square, ring at its yard spot', () {
      final plan = planFor(
        makeState(tokens: {
          0: [2, -1, -1, -1],
          1: [relativeFor(1, 5), -1, -1, -1],
        }, dice: 3),
        0,
      );
      expect(kinds(plan), {FxKind.shockwave, FxKind.dust});
      final shock =
          plan.effects.rings.firstWhere((r) => r.kind == FxKind.shockwave);
      expect(shock.ring.center, geo.trackCell(5));
      expect(shock.ring.startMs, plan.mover.impactMs);
      expect(shock.seat, 0);
      final land = plan.effects.rings.firstWhere((r) => r.kind == FxKind.dust);
      expect(land.seat, 1);
      expect(land.ring.center, geo.yardSpot(1, 0));
      expect(
        land.ring.startMs,
        plan.mover.impactMs + spec.captureShakeMs + spec.captureReturnMs,
      );
    });

    test('reaching home: 8 sparks and a pocket glow, no dust', () {
      final plan = planFor(
        makeState(tokens: {
          0: [54, -1, -1, -1],
        }, dice: 2),
        0,
        startMs: 400,
      );
      expect(plan.ring, isNotNull);
      expect(plan.effects.rings, isEmpty);
      final sparks = plan.effects.sparks.single.burst;
      expect(sparks.startMs, 400 + plan.mover.impactMs);
      expect(sparks.sample(sparks.startMs + 100), hasLength(8));
      final glow = plan.effects.glows.single;
      expect(
          glow.sample(glow.startMs + spec.pocketGlowMs / 2), closeTo(1, 1e-9));
    });

    test('reduced motion: nothing visible', () {
      const reduced = MotionSpec.reduced;
      final plan = planFor(
        makeState(tokens: {
          0: [54, -1, -1, -1],
        }, dice: 2),
        0,
        spec: reduced,
      );
      for (final s in plan.effects.sparks) {
        expect(s.burst.sample(s.burst.startMs + 50), isEmpty);
      }
      for (final g in plan.effects.glows) {
        expect(g.sample(g.startMs + 100), 0);
      }
      final dust = planFor(
        makeState(tokens: {
          0: [2, -1, -1, -1],
        }, dice: 3),
        0,
        spec: reduced,
      );
      for (final r in dust.effects.rings) {
        expect(r.ring.sample(r.ring.startMs + 10).opacity, 0);
      }
    });
  });

  group('FxScene', () {
    test('keeps effects until they end, then prunes them', () {
      final scene = FxScene();
      final plan = planFor(
        makeState(tokens: {
          0: [54, -1, -1, -1],
        }, dice: 2),
        0,
      );
      scene.addAll(plan.effects);
      scene.addNudge(
        const FxNudge(seat: 1, index: 2, startMs: 0),
        const Pt(3, 3),
        spec,
      );
      expect(scene.isEmpty, isFalse);
      expect(scene.particleCount, 8);
      expect(scene.nudgeOf(1, 2, 40, spec), isNot(0));
      expect(scene.nudgeOf(1, 3, 40, spec), 0);
      scene.prune(10000, spec);
      expect(scene.isEmpty, isTrue);
    });

    test('particle budget: confetti plus every spark stays <= 60 + 8 x 4', () {
      final burst = ConfettiBurst(origin: const Pt(0, 0), startMs: 0, seed: 3);
      expect(burst.count, lessThanOrEqualTo(60));
      // A move spawns at most one spark burst, so even four seats finishing
      // at once cannot exceed the budget by much.
      expect(spec.sparkCount * 4 + burst.count, lessThanOrEqualTo(92));
    });
  });

  group('FrameStats', () {
    FrameSample frame(double total, {double? gap, double paint = 1}) =>
        FrameSample(
          buildMs: total / 2,
          rasterMs: total / 2,
          totalMs: total,
          intervalMs: gap,
          paintMs: paint,
        );

    test('empty summary', () {
      expect(FrameStats().summary().frames, 0);
    });

    test('fps, drops and slow frames', () {
      final stats = FrameStats(capacity: 10);
      for (var i = 0; i < 9; i++) {
        stats.add(frame(8, gap: 16.67));
      }
      stats.add(frame(40, gap: 50));
      final s = stats.summary();
      expect(s.frames, 10);
      expect(s.droppedFrames, 1);
      expect(s.slowFrames, 1);
      expect(s.worstTotalMs, 40);
      expect(s.fps, closeTo(1000 * 10 / (9 * 16.67 + 50), 0.01));
    });

    test('a pause of the ticker is not a hitch', () {
      final stats = FrameStats();
      stats.add(frame(8, gap: 16.67));
      stats.add(frame(8, gap: 3000));
      expect(stats.summary().droppedFrames, 0);
    });

    test('keeps only the last `capacity` frames', () {
      final stats = FrameStats(capacity: 5);
      for (var i = 0; i < 20; i++) {
        stats.add(frame(i.toDouble()));
      }
      expect(stats.length, 5);
      expect(stats.summary().worstTotalMs, 19);
    });

    test('paint budget flag', () {
      final stats = FrameStats();
      stats.add(frame(8, paint: 3));
      expect(stats.summary().paintOverBudget, isFalse);
      stats.add(frame(8, paint: 5));
      expect(stats.summary().paintOverBudget, isTrue);
    });
  });

  group('PaintProbe', () {
    tearDown(() {
      PaintProbe.enabled = false;
      PaintProbe.reset();
    });

    test('does nothing while disabled', () {
      PaintProbe.stop(PaintProbe.start());
      expect(PaintProbe.nextFrame(), 0);
      expect(PaintProbe.averageMs, 0);
    });

    test('accumulates the time of a frame and closes it on nextFrame', () {
      PaintProbe.enabled = true;
      final stamp = PaintProbe.start();
      final until = DateTime.now().add(const Duration(milliseconds: 3));
      while (DateTime.now().isBefore(until)) {}
      PaintProbe.stop(stamp);
      final ms = PaintProbe.nextFrame();
      expect(ms, greaterThanOrEqualTo(2));
      expect(PaintProbe.lastFrameMs, ms);
      expect(PaintProbe.worstMs, ms);
      expect(PaintProbe.nextFrame(), 0);
    });
  });
}
