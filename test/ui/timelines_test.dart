import 'dart:math' as math;

import 'package:ludo/ui/core/dice_timeline.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/token_timeline.dart';
import 'package:test/test.dart';

void main() {
  const spec = MotionSpec.standard;

  group('DiceTimeline', () {
    test('standard roll lasts 600 ms', () {
      expect(DiceTimeline(value: 4).durationMs, 600);
    });

    for (var value = 1; value <= 6; value++) {
      test('value $value: only revealed at the end of the tumble', () {
        final dice = DiceTimeline(value: value);
        for (var t = 0.0; t < spec.diceTumbleMs; t += 4) {
          final pose = dice.sample(t);
          expect(pose.face, inInclusiveRange(1, 6));
          expect(pose.face, isNot(value), reason: 'leaked at $t ms');
        }
        for (var t = spec.diceTumbleMs; t <= dice.durationMs; t += 4) {
          expect(dice.sample(t).face, value);
        }
        final end = dice.sample(dice.durationMs);
        expect(end.face, value);
        expect(end.angle, closeTo(0, 1e-9));
        expect(end.scale, closeTo(1, 1e-9));
      });
    }

    test('starts three turns away and spins down monotonically', () {
      final dice = DiceTimeline(value: 3);
      expect(dice.sample(0).angle, closeTo(3 * 2 * math.pi, 1e-9));
      var last = double.infinity;
      for (var t = 0.0; t <= spec.diceTumbleMs; t += 8) {
        final a = dice.sample(t).angle;
        expect(a, lessThanOrEqualTo(last + 1e-9));
        last = a;
      }
    });

    test('the face changes 9 times, never to the same face twice in a row', () {
      final dice = DiceTimeline(value: 6);
      var changes = 0;
      var prev = dice.sample(0).face;
      for (var t = 1.0; t <= spec.diceTumbleMs; t++) {
        final f = dice.sample(t).face;
        if (f != prev) {
          changes++;
          prev = f;
        }
      }
      expect(changes, spec.diceFlickers);
    });

    test('reduced motion shows the result at once and fades in', () {
      final dice = DiceTimeline(value: 5, spec: MotionSpec.reduced);
      expect(dice.durationMs, 120);
      expect(dice.sample(0).face, 5);
      expect(dice.sample(0).opacity, 0);
      expect(dice.sample(120).opacity, 1);
      expect(dice.sample(60).angle, 0);
    });
  });

  group('PulseSample', () {
    test('stays inside its radius and opacity envelope and loops', () {
      for (var t = 0.0; t < 3 * spec.pulsePeriodMs; t += 7) {
        final p = PulseSample.at(t, spec);
        expect(
            p.radius,
            inInclusiveRange(spec.pulseMinRadius,
                spec.pulseMinRadius + spec.pulseRadiusGain + 1e-9));
        expect(
            p.opacity,
            inInclusiveRange(spec.pulseMinOpacity,
                spec.pulseMinOpacity + spec.pulseOpacityGain + 1e-9));
      }
      final a = PulseSample.at(123, spec);
      final b = PulseSample.at(123 + spec.pulsePeriodMs, spec);
      expect(a.radius, closeTo(b.radius, 1e-9));
    });

    test('peaks at half the period', () {
      final p = PulseSample.at(spec.pulsePeriodMs / 2, spec);
      expect(
          p.radius, closeTo(spec.pulseMinRadius + spec.pulseRadiusGain, 1e-9));
    });
  });

  group('TokenTimeline.hop', () {
    const a = Pt(1.5, 6.5);
    const b = Pt(2.5, 6.5);
    const c = Pt(3.5, 6.5);
    const d = Pt(4.5, 6.5);
    final tl = TokenTimeline.hop(path: const [a, b, c, d]);

    test('duration = steps x 130 + 100 and impact when the last hop lands', () {
      expect(tl.durationMs, 3 * 130 + 100);
      expect(tl.impactMs, 3 * 130);
    });

    test('starts on the first point and ends on the last, at rest', () {
      final start = tl.sample(0);
      expect(start.pos, a);
      expect(start.lift, 0);
      final end = tl.sample(tl.durationMs);
      expect(end.pos, d);
      expect(end.lift, 0);
      expect(end.scaleX, closeTo(1, 1e-9));
      expect(end.scaleY, closeTo(1, 1e-9));
    });

    test('hop apex is 0.35 cell at mid-step and never underground', () {
      expect(tl.sample(65).lift, closeTo(spec.hopArc, 1e-9));
      expect(tl.sample(130 + 65).lift, closeTo(spec.hopArc, 1e-9));
      for (var t = 0.0; t <= tl.durationMs; t += 3) {
        expect(tl.sample(t).lift, greaterThanOrEqualTo(0));
      }
    });

    test('position is continuous across step boundaries and clamps time', () {
      for (final boundary in [130.0, 260.0]) {
        final before = tl.sample(boundary - 1e-6).pos;
        final after = tl.sample(boundary + 1e-6).pos;
        expect(before.distanceTo(after), lessThan(1e-3));
      }
      expect(tl.sample(-50).pos, a);
      expect(tl.sample(99999).pos, d);
    });

    test('squash only happens after the last landing', () {
      for (var t = 0.0; t < tl.impactMs; t += 5) {
        expect(tl.sample(t).scaleY, 1);
      }
      final squash = tl.sample(tl.impactMs + 50);
      expect(squash.scaleY, closeTo(1 - spec.squashY, 1e-9));
      expect(squash.scaleX, closeTo(1 + spec.squashX, 1e-9));
    });

    test('is a pure function: same time, same pose', () {
      final x = tl.sample(201);
      tl.sample(10);
      final y = tl.sample(201);
      expect(x.pos, y.pos);
      expect(x.lift, y.lift);
    });

    test('yard exit is one higher, longer hop', () {
      final exit = TokenTimeline.hop(path: const [a, b], fromYard: true);
      expect(exit.durationMs, 220 + 100);
      expect(exit.sample(110).lift, closeTo(spec.yardExitArc, 1e-9));
      expect(exit.sample(exit.durationMs).pos, b);
    });

    test('finishing shrinks into the pocket instead of squashing', () {
      final fin = TokenTimeline.hop(path: const [a, b], toFinish: true);
      expect(fin.durationMs, 130 + 260);
      final end = fin.sample(fin.durationMs);
      expect(end.scaleX, closeTo(spec.finishScale, 1e-9));
      expect(end.scaleY, closeTo(spec.finishScale, 1e-9));
      // Overshoot below the target is allowed (easeOutBack) but bounded.
      for (var t = fin.impactMs; t <= fin.durationMs; t += 5) {
        expect(fin.sample(t).scaleX, inInclusiveRange(0.45, 1.0));
      }
    });

    test('reduced motion cross-fades instead of hopping', () {
      final r =
          TokenTimeline.hop(path: const [a, b, c, d], spec: MotionSpec.reduced);
      expect(r.durationMs, 240);
      expect(r.sample(0).pos, a);
      expect(r.sample(0).opacity, 1);
      expect(r.sample(120).opacity, closeTo(0, 1e-9));
      expect(r.sample(240).pos, d);
      expect(r.sample(240).opacity, 1);
      for (var t = 0.0; t <= 240; t += 5) {
        expect(r.sample(t).lift, 0);
      }
    });
  });

  group('TokenTimeline.captured', () {
    const square = Pt(6.5, 3.5);
    const yard = Pt(2, 2);
    final tl = TokenTimeline.captured(square: square, yard: yard);

    test('shakes 220 ms then flies home 420 ms', () {
      expect(tl.durationMs, 640);
      expect(tl.impactMs, 0);
    });

    test('shake stays within the amplitude and keeps the token in place', () {
      var maxDx = 0.0;
      for (var t = 0.0; t <= spec.captureShakeMs; t += 2) {
        final p = tl.sample(t);
        maxDx = math.max(maxDx, (p.pos.x - square.x).abs());
        expect(p.pos.y, square.y);
        expect(p.lift, 0);
      }
      expect(maxDx, greaterThan(0.03));
      expect(maxDx, lessThanOrEqualTo(spec.shakeAmplitude));
      expect(tl.sample(spec.captureShakeMs).pos.distanceTo(square),
          lessThan(1e-6));
    });

    test('flight arcs up and lands exactly on the yard spot', () {
      final mid = tl.sample(spec.captureShakeMs + spec.captureReturnMs / 2);
      expect(mid.lift, closeTo(spec.captureReturnArc, 1e-9));
      final end = tl.sample(tl.durationMs);
      expect(end.pos.distanceTo(yard), lessThan(1e-9));
      expect(end.lift, 0);
    });
  });

  group('RingBurst', () {
    const ring = RingBurst(center: Pt(7, 7), startMs: 100, spec: spec);

    test('invisible outside its lifetime, expanding and fading inside', () {
      expect(ring.sample(99).opacity, 0);
      expect(ring.sample(ring.endMs).opacity, 0);
      final early = ring.sample(120);
      final late = ring.sample(450);
      expect(early.radius, lessThan(late.radius));
      expect(early.opacity, greaterThan(late.opacity));
      expect(late.radius, lessThanOrEqualTo(spec.ringEndRadius));
      expect(early.opacity, lessThanOrEqualTo(spec.ringOpacity));
    });

    test('reduced motion never shows it', () {
      const r =
          RingBurst(center: Pt(7, 7), startMs: 0, spec: MotionSpec.reduced);
      expect(r.sample(10).opacity, 0);
    });
  });
}
