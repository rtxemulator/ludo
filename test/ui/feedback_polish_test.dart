import 'dart:math' as math;

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/fx.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/revert_plan.dart';
import 'package:ludo/ui/core/token_timeline.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

/// Polish pass 1, step 7 (feedback): the bowed capture flight, the home
/// burst, the big toast and the path-following rewind.
const _spec = MotionSpec.standard;
const _geo = BoardGeometry();

/// Distance of [p] from the segment [a]..[b].
double _distToSegment(Pt p, Pt a, Pt b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) {
    return p.distanceTo(a);
  }
  final u = (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
  return p.distanceTo(Pt(a.x + dx * u, a.y + dy * u));
}

double _distToPath(Pt p, List<Pt> path) {
  var best = double.infinity;
  for (var i = 0; i + 1 < path.length; i++) {
    best = math.min(best, _distToSegment(p, path[i], path[i + 1]));
  }
  return best;
}

void main() {
  group('captured flight is an arc', () {
    const square = Pt(6.5, 3.5);
    const yard = Pt(2, 2);
    final tl = TokenTimeline.captured(square: square, yard: yard);
    final mid = _spec.captureShakeMs + _spec.captureReturnMs / 2;

    test('it leaves the straight line in the middle and meets it at both ends',
        () {
      final line = _distToSegment(tl.sample(mid).pos, square, yard);
      expect(line, greaterThan(0.3));
      expect(line, lessThanOrEqualTo(_spec.captureBowMax + 1e-9));
      expect(_distToSegment(tl.sample(_spec.captureShakeMs).pos, square, yard),
          lessThan(1e-9));
      expect(tl.sample(tl.durationMs).pos.distanceTo(yard), lessThan(1e-9));
    });

    test('the bow is away from the board centre', () {
      const centre = Pt(7.5, 7.5);
      final straightMid = Pt.lerp(square, yard, 0.5);
      final bowed = tl.sample(mid).pos;
      expect(bowed.distanceTo(centre),
          greaterThan(straightMid.distanceTo(centre)));
    });

    test('the same flight from the opposite side bows the opposite way', () {
      final a = TokenTimeline.captured(
          square: const Pt(8.5, 11.5), yard: const Pt(13, 13));
      final b = TokenTimeline.captured(
          square: const Pt(6.5, 3.5), yard: const Pt(2, 2));
      const centre = Pt(7.5, 7.5);
      for (final t in [a, b]) {
        final p = t.sample(mid).pos;
        expect(p.x, inInclusiveRange(0, 15));
        expect(p.y, inInclusiveRange(0, 15));
      }
      // Both bow outward: farther from the centre than their straight line.
      expect(
        a.sample(mid).pos.distanceTo(centre),
        greaterThan(Pt.lerp(const Pt(8.5, 11.5), const Pt(13, 13), 0.5)
            .distanceTo(centre)),
      );
    });

    test('a flight of no length does not bow or break', () {
      final same = TokenTimeline.captured(square: yard, yard: yard);
      expect(same.sample(mid).pos.distanceTo(yard), lessThan(1e-9));
    });

    test('the shake is tiny (at most 0.08 cell) and the haptic hook is intact',
        () {
      expect(_spec.shakeAmplitude, lessThanOrEqualTo(0.08));
      var maxDx = 0.0;
      for (var t = 0.0; t <= _spec.captureShakeMs; t += 2) {
        maxDx = math.max(maxDx, (tl.sample(t).pos.x - square.x).abs());
      }
      expect(maxDx, greaterThan(0.02));
      expect(maxDx, lessThanOrEqualTo(_spec.shakeAmplitude));
    });

    test('reduced motion still jumps', () {
      final r = TokenTimeline.captured(
          square: square, yard: yard, spec: MotionSpec.reduced);
      expect(r.sample(r.durationMs).pos.distanceTo(yard), lessThan(1e-9));
    });
  });

  group('home burst', () {
    final burst = SparkBurst(center: const Pt(7.5, 7.5), startMs: 0, seed: 11);

    test('14 sparks with different reaches and sizes', () {
      final sparks = burst.sample(250);
      expect(sparks, hasLength(14));
      final sizes = {for (final s in sparks) (s.size * 1000).round()};
      final reach = {
        for (final s in sparks)
          (s.pos.distanceTo(const Pt(7.5, 7.5)) * 100).round()
      };
      expect(sizes.length, greaterThan(4));
      expect(reach.length, greaterThan(4));
    });

    test('every other spark is a streak that shrinks to nothing', () {
      final early = burst.sample(40);
      final late = burst.sample(_spec.sparkMs - 5);
      expect(
          [for (var i = 0; i < early.length; i++) early[i].tail > 0 ? i : -1]
              .where((i) => i >= 0)
              .length,
          7);
      expect(early.where((s) => s.tail > 0).first.tail,
          greaterThan(late.where((s) => s.tail > 0).first.tail));
      for (final s in early) {
        expect(s.tail, lessThanOrEqualTo(_spec.sparkTail + 1e-9));
        expect(s.tail, greaterThanOrEqualTo(0));
      }
    });

    test('sparks fly along their own angle', () {
      for (final s in burst.sample(200)) {
        final v = Pt(s.pos.x - 7.5, s.pos.y - 7.5);
        expect(math.atan2(v.y, v.x),
            closeTo(math.atan2(math.sin(s.angle), math.cos(s.angle)), 1e-6));
      }
    });

    test('the budget holds: confetti + one burst <= 40', () {
      expect(_spec.confettiCount + _spec.sparkCount,
          lessThanOrEqualTo(_spec.maxParticles));
      expect(
          ConfettiBurst(origin: Pt.zero, startMs: 0).count + _spec.sparkCount,
          lessThanOrEqualTo(40));
    });
  });

  group('big toast', () {
    test('lives 2.2 s, fades at both ends, pops in from smaller', () {
      expect(toastLook(-1, 0, _spec, big: true).opacity, 0);
      expect(toastLook(1100, 0, _spec, big: true).opacity, 1);
      expect(toastLook(1100, 0, _spec, big: true).scale, closeTo(1, 1e-9));
      expect(toastLook(_spec.toastMs + 50, 0, _spec, big: true).opacity, 1);
      expect(toastLook(_spec.toastMs + 50, 0, _spec).opacity, 0);
      expect(toastLook(_spec.toastBigMs, 0, _spec, big: true).opacity, 0);
      expect(toastLook(5, 0, _spec, big: true).scale,
          lessThan(toastLook(5, 0, _spec).scale));
    });

    test('reduced motion: fade only', () {
      expect(toastLook(300, 0, MotionSpec.reduced, big: true).scale, 1);
    });

    test('a faster speed shortens it', () {
      expect(
          _spec.scaled(1.6).toastBigMs, closeTo(_spec.toastBigMs / 1.6, 1e-9));
    });
  });

  group('TokenTimeline.rewind', () {
    const path = [Pt(10, 1), Pt(9, 1), Pt(8, 1), Pt(7, 1), Pt(6, 1)];
    final tl = TokenTimeline.rewind(path: path);

    test('starts on the first point, lands on the last, ends at rest', () {
      expect(tl.sample(0).pos, path.first);
      final end = tl.sample(tl.durationMs);
      expect(end.pos.distanceTo(path.last), lessThan(1e-9));
      expect(end.scale, closeTo(1, 1e-9));
      expect(end.lift, 0);
    });

    test('stays on the path, never goes forward, rises a little', () {
      var lastX = 10.0 + 1e-9;
      var peak = 0.0;
      for (var t = 0.0; t <= tl.impactMs; t += 5) {
        final p = tl.sample(t);
        expect(_distToPath(p.pos, path), lessThan(1e-9));
        expect(p.pos.x, lessThanOrEqualTo(lastX));
        lastX = p.pos.x;
        peak = math.max(peak, p.lift);
      }
      expect(peak, closeTo(_spec.rewindLift, 0.01));
    });

    test('4 steps take the 300 ms minimum, 56 steps the 900 ms maximum', () {
      expect(tl.impactMs, _spec.rewindMinMs);
      final long = TokenTimeline.rewind(
        path: [for (var i = 0; i < 57; i++) Pt(i * 0.2, 1)],
      );
      expect(long.impactMs, _spec.rewindMaxMs);
      final mid = TokenTimeline.rewind(
        path: [for (var i = 0; i < 9; i++) Pt(8.0 - i, 1)],
      );
      expect(mid.impactMs, 8 * _spec.rewindStepMs);
    });

    test('follows a bend (the path, not the chord)', () {
      const bent = [Pt(0, 0), Pt(4, 0), Pt(4, 4)];
      final b = TokenTimeline.rewind(path: bent);
      final p = b.sample(b.impactMs / 2).pos;
      expect(_distToPath(p, bent), lessThan(1e-9));
      expect(_distToSegment(p, bent.first, bent.last), greaterThan(0.5));
    });

    test('reduced motion cross-fades', () {
      final r = TokenTimeline.rewind(path: path, spec: MotionSpec.reduced);
      expect(r.durationMs, 2 * MotionSpec.reduced.reducedFadeMs);
      expect(r.sample(r.durationMs).pos, path.last);
    });
  });

  group('RevertAnimation rewinds along the path', () {
    const banked = RulesConfig(bankedRolls: true);

    test('a token that walked forward slides back over the same squares', () {
      final before = makeState(rules: banked, tokens: {
        0: [14, -1, -1, -1],
      });
      final after = makeState(rules: banked, tokens: {
        0: [8, -1, -1, -1],
      });
      final plan = RevertAnimation.plan(before: before, after: after);
      final squares = [
        for (var p = 14; p >= 8; p--) _geo.cellCenter(0, p, 0),
      ];
      for (var t = 0.0; t <= plan.totalMs; t += 10) {
        final pose = plan.poseOf(0, 0, t)!;
        expect(_distToPath(pose.pos, squares), lessThan(1e-9), reason: 't=$t');
      }
      expect(plan.poseOf(0, 0, plan.totalMs)!.pos.distanceTo(squares.last),
          lessThan(1e-9));
    });

    test('a token that left its yard goes back through the start square', () {
      final before = makeState(rules: banked, tokens: {
        0: [5, -1, -1, -1],
      });
      final after = makeState(rules: banked, tokens: {
        0: [-1, -1, -1, -1],
      });
      final plan = RevertAnimation.plan(before: before, after: after);
      final start = _geo.cellCenter(0, 0, 0);
      final yard = _geo.yardSpot(0, 0);
      final path = [
        for (var p = 5; p >= 0; p--) _geo.cellCenter(0, p, 0),
        yard,
      ];
      var passedStart = false;
      for (var t = 0.0; t <= plan.totalMs; t += 5) {
        final pose = plan.poseOf(0, 0, t)!;
        expect(_distToPath(pose.pos, path), lessThan(1e-9), reason: 't=$t');
        if (pose.pos.distanceTo(start) < 0.05) {
          passedStart = true;
        }
      }
      expect(passedStart, isTrue);
      expect(plan.poseOf(0, 0, plan.totalMs)!.pos.distanceTo(yard),
          lessThan(1e-9));
    });

    test('a captured token still flies back from its yard', () {
      final before = makeState(rules: banked, tokens: {
        0: [14, -1, -1, -1],
        1: [-1, -1, -1, -1],
      });
      final after = makeState(rules: banked, tokens: {
        0: [10, -1, -1, -1],
        1: [relativeFor(1, 14), -1, -1, -1],
      });
      final plan = RevertAnimation.plan(before: before, after: after);
      final victim = plan.tokens.firstWhere((t) => t.seat == 1);
      expect(victim.timeline.impactMs, _spec.revertMs);
      final mover = plan.tokens.firstWhere((t) => t.seat == 0);
      expect(mover.timeline.impactMs, _spec.rewindMinMs);
    });

    test('a long walk rewinds in no more than the 900 ms maximum', () {
      final before = makeState(rules: banked, tokens: {
        0: [50, -1, -1, -1],
      });
      final after = makeState(rules: banked, tokens: {
        0: [3, -1, -1, -1],
      });
      final plan = RevertAnimation.plan(before: before, after: after);
      expect(plan.totalMs, _spec.rewindMaxMs + _spec.landSquashMs);
    });

    test('reduced motion: a quick fade, nothing travels', () {
      final before = makeState(rules: banked, tokens: {
        0: [14, -1, -1, -1]
      });
      final after = makeState(rules: banked, tokens: {
        0: [8, -1, -1, -1]
      });
      final plan = RevertAnimation.plan(
          before: before, after: after, spec: MotionSpec.reduced);
      expect(plan.totalMs, 2 * MotionSpec.reduced.reducedFadeMs);
    });
  });
}
