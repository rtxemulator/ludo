import 'dart:math' as math;

import 'package:ludo/ui/core/dice3d.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/rot3.dart';
import 'package:ludo/ui/core/seeded.dart';
import 'package:test/test.dart';

/// The value of the face that looks most directly at the viewer.
int topFace(Mat3 r) => visibleFaces(r).last.value;

void main() {
  const spec = MotionSpec.standard;
  const d = Dice3dSpec();

  group('cube', () {
    test('opposite faces sum to 7 and frames are right-handed and unit', () {
      for (final f in dieFaces) {
        final opposite = dieFaces.firstWhere(
          (o) => (o.normal + f.normal).length < 1e-9,
        );
        expect(f.value + opposite.value, 7);
        expect(f.u.cross(f.v).dot(f.normal), closeTo(1, 1e-12));
        expect(f.u.length, closeTo(1, 1e-12));
        expect(f.v.length, closeTo(1, 1e-12));
        expect(f.u.dot(f.normal), 0);
        expect(f.v.dot(f.normal), 0);
      }
      expect(dieFaces.map((f) => f.value).toSet(), {1, 2, 3, 4, 5, 6});
    });

    test('pip layouts have the right counts and stay on the face', () {
      for (var v = 1; v <= 6; v++) {
        final pips = pipLayout(v);
        expect(pips.length, v);
        for (final p in pips) {
          expect(p.x.abs(), lessThanOrEqualTo(0.25));
          expect(p.y.abs(), lessThanOrEqualTo(0.25));
        }
      }
      expect(() => pipLayout(7), throwsArgumentError);
    });

    test('rotation matrices are orthonormal and compose', () {
      final r = Mat3.axisAngle(const Vec3(1, 2, 3), 1.234);
      final x = r.apply(const Vec3(1, 0, 0));
      final y = r.apply(const Vec3(0, 1, 0));
      expect(x.length, closeTo(1, 1e-12));
      expect(x.dot(y), closeTo(0, 1e-12));
      final back = r * Mat3.axisAngle(const Vec3(1, 2, 3), -1.234);
      expect(back.maxDifference(Mat3.identity), lessThan(1e-12));
    });
  });

  group('finalOrientation', () {
    test('every value ends up on top, for any yaw', () {
      for (var value = 1; value <= 6; value++) {
        for (final yaw in [0.0, 0.3, -0.6, 1.2]) {
          final r = finalOrientation(value, yaw: yaw);
          final face = dieFaces.firstWhere((f) => f.value == value);
          final n = r.apply(face.normal);
          expect(n.x, closeTo(0, 1e-12), reason: 'value $value');
          expect(n.y, closeTo(0, 1e-12));
          expect(n.z, closeTo(1, 1e-12));
          expect(topFace(r), value);
          // The opposite face looks away from the viewer.
          final opposite = dieFaces.firstWhere((f) => f.value == 7 - value);
          expect(r.apply(opposite.normal).z, closeTo(-1, 1e-12));
        }
      }
    });

    test('rejects values outside 1..6', () {
      expect(() => finalOrientation(0), throwsArgumentError);
      expect(() => finalOrientation(7), throwsArgumentError);
    });
  });

  group('visibleFaces', () {
    test('at rest only the top face shows', () {
      for (var v = 1; v <= 6; v++) {
        final faces = visibleFaces(finalOrientation(v, yaw: 0.2));
        expect(faces.length, 1);
        expect(faces.single.value, v);
        expect(faces.single.shade, closeTo(1, 1e-12));
      }
    });

    test('random orientations: <= 3 faces and <= 18 pips per frame', () {
      final rnd = Seeded(77);
      for (var i = 0; i < 3000; i++) {
        final axis = Vec3(rnd.spread(1), rnd.spread(1), rnd.spread(1));
        final r = Mat3.axisAngle(axis, rnd.range(0, 2 * math.pi)) *
            Mat3.rotationZ(rnd.range(0, 2 * math.pi));
        final faces = visibleFaces(r);
        expect(faces.length, inInclusiveRange(1, 3));
        expect(
            faces.fold<int>(0, (n, f) => n + f.value), lessThanOrEqualTo(18));
        for (var k = 1; k < faces.length; k++) {
          expect(faces[k].normalZ, greaterThanOrEqualTo(faces[k - 1].normalZ));
        }
        for (final f in faces) {
          expect(f.shade, inInclusiveRange(0.55, 1.0));
        }
      }
    });
  });

  group('Dice3dTimeline', () {
    test('timing: ~0.92 s to settle, 1.12 s with the reveal', () {
      final t = Dice3dTimeline(value: 3, seed: 1);
      expect(t.settleMs, 920);
      expect(t.durationMs, 1120);
      expect(t.impactsMs, [420, 650, 800]);
    });

    test('the rolled face is on top from the last impact on, any seed', () {
      for (var value = 1; value <= 6; value++) {
        for (var seed = 0; seed < 40; seed++) {
          final t = Dice3dTimeline(value: value, seed: seed);
          for (var ms = d.bounce3EndMs; ms <= t.durationMs; ms += 10) {
            expect(
              topFace(t.sample(ms).rotation),
              value,
              reason: 'value $value seed $seed at $ms',
            );
          }
        }
      }
    });

    test('exactly the final orientation once the wobble has died', () {
      final t = Dice3dTimeline(value: 5, seed: 8);
      expect(
        t.sample(d.settleEndMs).rotation.maxDifference(t.finalRotation),
        lessThan(1e-9),
      );
      expect(
        t.sample(t.durationMs).rotation.maxDifference(t.finalRotation),
        lessThan(1e-9),
      );
    });

    test('the settle wobble stays within +-4 degrees of the final yaw', () {
      final t = Dice3dTimeline(value: 2, seed: 3);
      var maxAngle = 0.0;
      for (var ms = d.bounce3EndMs; ms <= d.settleEndMs; ms += 2) {
        final diff = t.sample(ms).rotation * t.finalRotation.transposed;
        // Rotation about z only: angle from the top-left 2x2 block.
        final angle = math.atan2(diff.at(1, 0), diff.at(0, 0)).abs();
        maxAngle = math.max(maxAngle, angle);
      }
      expect(maxAngle, greaterThan(0.01));
      expect(maxAngle, lessThanOrEqualTo(4 * math.pi / 180 + 1e-9));
    });

    test('bounce apexes decay: 1.6 > 0.55 > 0.18 cells, never underground', () {
      final t = Dice3dTimeline(value: 4, seed: 11);
      double apex(double from, double to) {
        var m = 0.0;
        for (var ms = from; ms < to; ms += 1) {
          final h = t.sample(ms).height;
          expect(h, greaterThanOrEqualTo(0));
          m = math.max(m, h);
        }
        return m;
      }

      final a1 = apex(d.popInMs, d.flightEndMs);
      final a2 = apex(d.flightEndMs, d.bounce2EndMs);
      final a3 = apex(d.bounce2EndMs, d.bounce3EndMs);
      expect(a1, closeTo(d.flightApex, 1e-3));
      expect(a2, closeTo(d.bounce2Apex, 1e-3));
      expect(a3, closeTo(d.bounce3Apex, 1e-3));
      expect(a1, greaterThan(a2));
      expect(a2, greaterThan(a3));
      expect(t.sample(d.bounce3EndMs).height, 0);
      expect(t.sample(d.settleEndMs).height, 0);
    });

    test('height is on the ground at the pop-in and at each impact', () {
      final t = Dice3dTimeline(value: 1, seed: 2);
      expect(t.sample(0).height, 0);
      for (final impact in t.impactsMs) {
        expect(t.sample(impact).height, closeTo(0, 1e-9));
      }
    });

    test('scale: pop-in 0.6 -> 1.1 -> 1, +45% at the apex, press at impacts',
        () {
      final t = Dice3dTimeline(value: 6, seed: 4);
      expect(t.sample(0).scale, closeTo(0.6, 1e-9));
      var peak = 0.0;
      for (var ms = 0.0; ms <= d.popInMs; ms += 1) {
        peak = math.max(peak, t.sample(ms).scale);
      }
      expect(peak, closeTo(1.1, 1e-3));
      expect(t.sample(d.popInMs).scale, closeTo(1, 1e-9));
      final apexMs = (d.popInMs + d.flightEndMs) / 2;
      expect(t.sample(apexMs).scale, closeTo(1.45, 1e-6));
      for (final impact in t.impactsMs) {
        // Divide out the height scale: the die is already rising again.
        final mid = t.sample(impact + d.pressMs / 2);
        final press = mid.scale / (1 + d.liftScalePerCell * mid.height);
        expect(press, closeTo(d.pressScale, 1e-9));
        final after = t.sample(impact + d.pressMs);
        expect(
          after.scale / (1 + d.liftScalePerCell * after.height),
          closeTo(1, 1e-9),
        );
      }
      expect(t.sample(t.durationMs).scale, closeTo(1, 1e-9));
    });

    test('the shadow widens and fades with height', () {
      final t = Dice3dTimeline(value: 3, seed: 6);
      final ground = t.sample(d.settleEndMs);
      final apex = t.sample((d.popInMs + d.flightEndMs) / 2);
      expect(ground.shadowScale, 1);
      expect(ground.shadowOpacity, 1);
      expect(apex.shadowScale, greaterThan(1.9));
      expect(apex.shadowOpacity, lessThan(0.4));
    });

    test('it moves from the hand toward the landing spot, never back', () {
      final t = Dice3dTimeline(value: 2, seed: 9);
      var last = double.infinity;
      for (var ms = d.popInMs; ms <= d.settleEndMs; ms += 2) {
        final dist = t.sample(ms).offset.distanceTo(t.landing);
        expect(dist, lessThanOrEqualTo(last + 1e-9), reason: 'at $ms');
        last = dist;
      }
      expect(
          t.sample(d.settleEndMs).offset.distanceTo(t.landing), lessThan(1e-9));
      // Leaves from the player's side (+y), lands near the dock centre.
      expect(t.sample(0).offset.y, closeTo(d.handDistance, 1e-9));
      expect(t.landing.x.abs(), lessThanOrEqualTo(d.landingJitter));
      expect(t.landing.y.abs(), lessThanOrEqualTo(d.landingJitter));
    });

    test('deterministic per (value, seed), different across seeds', () {
      final a = Dice3dTimeline(value: 4, seed: 123);
      final b = Dice3dTimeline(value: 4, seed: 123);
      final c = Dice3dTimeline(value: 4, seed: 124);
      for (var ms = 0.0; ms <= a.durationMs; ms += 37) {
        final pa = a.sample(ms);
        final pb = b.sample(ms);
        expect(pa.offset, pb.offset);
        expect(pa.height, pb.height);
        expect(pa.rotation.maxDifference(pb.rotation), 0);
      }
      expect(a.landing, isNot(c.landing));
      expect(
        a.sample(200).rotation.maxDifference(c.sample(200).rotation),
        greaterThan(1e-3),
      );
      // Sampling out of order does not matter.
      final x = a.sample(333).offset;
      a.sample(10);
      expect(a.sample(333).offset, x);
    });

    test('the yaw is bounded', () {
      for (var seed = 0; seed < 100; seed++) {
        final t = Dice3dTimeline(value: 1 + seed % 6, seed: seed);
        expect(t.yaw.abs(), lessThanOrEqualTo(d.maxYawDegrees * math.pi / 180));
      }
    });

    test('the reveal ring and six halo only appear after the settle', () {
      final six = Dice3dTimeline(value: 6, seed: 1);
      final three = Dice3dTimeline(value: 3, seed: 1);
      for (var ms = 0.0; ms < d.settleEndMs; ms += 5) {
        expect(six.sample(ms).ringOpacity, 0);
        expect(six.sample(ms).goldOpacity, 0);
      }
      final mid = (d.settleEndMs + d.revealEndMs) / 2;
      expect(six.sample(mid).ringOpacity, greaterThan(0));
      expect(six.sample(mid).goldOpacity, closeTo(1, 1e-9));
      expect(three.sample(mid).goldOpacity, 0);
      expect(three.sample(mid).ringOpacity, greaterThan(0));
      expect(six.sample(six.durationMs).ringOpacity, 0);
    });

    test('reduced motion: fade-in on the result, no tumble, no impacts', () {
      final t = Dice3dTimeline(
        value: 5,
        seed: 3,
        spec: MotionSpec.reduced,
      );
      expect(t.durationMs, 120);
      expect(t.settleMs, 120);
      expect(t.impactsMs, isEmpty);
      expect(t.sample(0).opacity, 0);
      expect(t.sample(120).opacity, 1);
      for (var ms = 0.0; ms <= 120; ms += 10) {
        final p = t.sample(ms);
        expect(topFace(p.rotation), 5);
        expect(p.height, 0);
        expect(p.scale, 1);
      }
    });
  });

  test('landing jitter stays inside the dock', () {
    // A 3.5 x 4.5 cell dock holds a 1.9 cell die with its jitter.
    final t = Dice3dTimeline(value: 1, seed: 1);
    expect(spec.dice3d.dieCells / 2 + t.landing.distanceTo(Pt.zero),
        lessThan(1.75));
  });
}
