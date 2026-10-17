import 'dart:math' as math;

import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/pulse.dart';
import 'package:ludo/ui/core/token_timeline.dart';
import 'package:test/test.dart';

void main() {
  const spec = MotionSpec.standard;

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
      expect(end.scale, closeTo(1, 1e-9));
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

    test('height is scale: 1 + gain x lift, never smaller than 1 in the air',
        () {
      expect(tl.sample(65).scale,
          closeTo(1 + spec.liftScaleGain * spec.hopArc, 1e-9));
      for (var t = 0.0; t < tl.impactMs; t += 3) {
        final pose = tl.sample(t);
        expect(pose.scale, closeTo(1 + spec.liftScaleGain * pose.lift, 1e-9));
        expect(pose.scale, greaterThanOrEqualTo(1));
      }
    });

    test('landing is a uniform press 1 -> 0.9 -> 1 after the last landing', () {
      final mid = tl.sample(tl.impactMs + spec.landSquashMs / 2);
      expect(mid.scale, closeTo(spec.pressScale, 1e-9));
      expect(mid.lift, 0);
      for (var t = tl.impactMs; t <= tl.durationMs; t += 2) {
        expect(tl.sample(t).scale,
            inInclusiveRange(spec.pressScale - 1e-9, 1 + 1e-9));
      }
      expect(tl.sample(tl.impactMs).scale, closeTo(1, 1e-9));
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
      expect(end.scale, closeTo(spec.finishScale, 1e-9));
      // Overshoot below the target is allowed (easeOutBack) but bounded.
      for (var t = fin.impactMs; t <= fin.durationMs; t += 5) {
        expect(fin.sample(t).scale, inInclusiveRange(0.45, 1.0));
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
    TokenPose mid(TokenTimeline t) =>
        t.sample(spec.captureShakeMs + spec.captureReturnMs / 2);

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
      expect(end.scale, closeTo(1, 1e-9));
    });

    test('the flight is bigger in the air (scale = 1 + gain x lift)', () {
      expect(mid(tl).scale,
          closeTo(1 + spec.liftScaleGain * spec.captureReturnArc, 1e-9));
      expect(tl.sample(50).scale, 1);
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
