import 'dart:math' as math;

import 'package:ludo/ui/core/fx.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/seeded.dart';
import 'package:test/test.dart';

void main() {
  const spec = MotionSpec.standard;

  group('Seeded', () {
    test('is deterministic and in range', () {
      final a = Seeded(42);
      final b = Seeded(42);
      for (var i = 0; i < 200; i++) {
        final x = a.next();
        expect(x, b.next());
        expect(x, inInclusiveRange(0.0, 1.0));
        expect(x, lessThan(1.0));
      }
      expect(Seeded(1).next(), isNot(Seeded(2).next()));
    });
  });

  group('RingFx', () {
    final dust = RingFx.dust(center: const Pt(3, 3), startMs: 50);
    final shock = RingFx.shockwave(center: const Pt(3, 3), startMs: 0);

    test('dust: 0.5 -> 0.9 cells, alpha 0.25 -> 0 over 160 ms', () {
      expect(dust.endMs, 50 + 160);
      expect(dust.sample(49).opacity, 0);
      expect(dust.sample(dust.endMs).opacity, 0);
      final first = dust.sample(50);
      expect(first.radius, closeTo(0.5, 1e-9));
      expect(first.opacity, closeTo(0.25, 1e-9));
      final last = dust.sample(dust.endMs - 1e-6);
      expect(last.radius, closeTo(0.9, 1e-3));
      expect(last.opacity, closeTo(0, 1e-3));
    });

    test('shockwave: 0.4 -> 1.2 cells over 260 ms', () {
      expect(shock.endMs, 260);
      expect(shock.sample(0).radius, closeTo(0.4, 1e-9));
      expect(shock.sample(259.999).radius, closeTo(1.2, 1e-3));
    });

    test('radius grows and opacity decays monotonically', () {
      for (final ring in [dust, shock]) {
        var radius = -1.0;
        var opacity = 2.0;
        for (var t = ring.startMs; t < ring.endMs; t += 2) {
          final s = ring.sample(t);
          expect(s.radius, greaterThanOrEqualTo(radius - 1e-12));
          expect(s.opacity, lessThanOrEqualTo(opacity + 1e-12));
          radius = s.radius;
          opacity = s.opacity;
        }
      }
    });

    test('reduced motion hides rings', () {
      final r = RingFx.shockwave(
        center: Pt.zero,
        startMs: 0,
        spec: MotionSpec.reduced,
      );
      expect(r.sample(10).opacity, 0);
    });
  });

  group('SparkBurst', () {
    final burst = SparkBurst(center: const Pt(7.5, 7.5), startMs: 100, seed: 9);

    test('8 sparks, none outside the lifetime', () {
      expect(burst.sample(99), isEmpty);
      expect(burst.sample(burst.endMs), isEmpty);
      expect(burst.sample(200).length, 8);
    });

    test('they fly radially, never beyond 0.9 cell, and fade', () {
      var farthest = 0.0;
      var opacity = 2.0;
      for (var t = 100.0; t < burst.endMs; t += 5) {
        final sparks = burst.sample(t);
        for (final s in sparks) {
          final d = s.pos.distanceTo(const Pt(7.5, 7.5));
          farthest = math.max(farthest, d);
          expect(d, lessThanOrEqualTo(spec.sparkDistance + 1e-9));
          expect(s.opacity, inInclusiveRange(0.0, 1.0));
        }
        expect(sparks.first.opacity, lessThanOrEqualTo(opacity + 1e-12));
        opacity = sparks.first.opacity;
      }
      expect(farthest, greaterThan(0.6));
    });

    test('sparks spread evenly around the pocket', () {
      final sparks = burst.sample(300);
      var minD = double.infinity;
      for (var i = 0; i < sparks.length; i++) {
        for (var j = i + 1; j < sparks.length; j++) {
          minD = math.min(minD, sparks[i].pos.distanceTo(sparks[j].pos));
        }
      }
      expect(minD, greaterThan(0.1));
    });

    test('same seed, same sparks; reduced motion shows none', () {
      final again =
          SparkBurst(center: const Pt(7.5, 7.5), startMs: 100, seed: 9);
      expect(again.sample(250).first.pos, burst.sample(250).first.pos);
      final r = SparkBurst(
        center: Pt.zero,
        startMs: 0,
        spec: MotionSpec.reduced,
      );
      expect(r.sample(50), isEmpty);
    });
  });

  group('pocketGlow', () {
    test('0 -> 1 -> 0 over 500 ms', () {
      expect(pocketGlow(99, 100, spec), 0);
      expect(pocketGlow(100, 100, spec), closeTo(0, 1e-9));
      expect(pocketGlow(350, 100, spec), closeTo(1, 1e-9));
      expect(pocketGlow(600, 100, spec), 0);
      expect(pocketGlow(350, 100, MotionSpec.reduced), 0);
    });
  });

  group('coinFlipScaleX', () {
    test('starts at 1, crosses zero three times, ends at -1', () {
      expect(coinFlipScaleX(0, spec), closeTo(1, 1e-12));
      expect(coinFlipScaleX(1, spec), closeTo(-1, 1e-12));
      var crossings = 0;
      var prev = coinFlipScaleX(0, spec);
      for (var i = 1; i <= 1000; i++) {
        final v = coinFlipScaleX(i / 1000, spec);
        if (v.sign != prev.sign) {
          crossings++;
        }
        prev = v;
      }
      expect(crossings, 3);
    });
  });

  group('ConfettiBurst', () {
    final burst =
        ConfettiBurst(origin: const Pt(7.5, 7.5), startMs: 0, seed: 5);

    test('at most 60 particles', () {
      expect(burst.count, lessThanOrEqualTo(60));
      expect(burst.count, 60);
      for (var t = 0.0; t < burst.endMs; t += 100) {
        expect(burst.sample(t).length, lessThanOrEqualTo(60));
      }
    });

    test('deterministic for a seed, different for another', () {
      final a = ConfettiBurst(origin: const Pt(7.5, 7.5), startMs: 0, seed: 5);
      final b = ConfettiBurst(origin: const Pt(7.5, 7.5), startMs: 0, seed: 6);
      final p = burst.sample(800);
      final q = a.sample(800);
      expect(p.length, q.length);
      for (var i = 0; i < p.length; i++) {
        expect(p[i].pos, q[i].pos);
        expect(p[i].rotation, q[i].rotation);
      }
      expect(b.sample(800).first.pos, isNot(p.first.pos));
    });

    test('nothing before the start or after the end', () {
      expect(burst.sample(-1), isEmpty);
      expect(burst.sample(burst.endMs), isEmpty);
    });

    test('pieces fade out before the end and use valid colour indices', () {
      final late = burst.sample(burst.endMs - 1);
      for (final p in late) {
        expect(p.opacity, lessThan(0.05));
      }
      for (final p in burst.sample(1000)) {
        expect(p.colorIndex, inInclusiveRange(0, 3));
        expect(p.opacity, inInclusiveRange(0.0, 1.0));
      }
    });

    test('flies outward from the origin without gravity bias', () {
      var cx = 0.0;
      var cy = 0.0;
      final pieces = burst.sample(2000);
      for (final p in pieces) {
        cx += p.pos.x - 7.5;
        cy += p.pos.y - 7.5;
      }
      // Centroid stays near the origin: no preferred direction.
      expect((cx / pieces.length).abs(), lessThan(1.5));
      expect((cy / pieces.length).abs(), lessThan(1.5));
    });

    test('reduced motion shows none', () {
      final r = ConfettiBurst(
        origin: Pt.zero,
        startMs: 0,
        spec: MotionSpec.reduced,
      );
      expect(r.sample(500), isEmpty);
    });
  });
}
