import 'dart:math' as math;

import 'package:ludo/ui/core/atmosphere.dart';
import 'package:ludo/ui/core/contrast.dart';
import 'package:ludo/ui/core/palette_spec.dart';
import 'package:test/test.dart';

/// Polish pass 1, step 8: the atmosphere numbers, the grain points and the
/// Classic colour change.
double _hue(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255;
  final g = ((argb >> 8) & 0xFF) / 255;
  final b = (argb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b));
  final mn = math.min(r, math.min(g, b));
  final d = mx - mn;
  if (d == 0) {
    return 0;
  }
  final h = mx == r
      ? ((g - b) / d) % 6
      : mx == g
          ? (b - r) / d + 2
          : (r - g) / d + 4;
  return h * 60;
}

double _hueGap(int a, int b) {
  final d = (_hue(a) - _hue(b)).abs();
  return math.min(d, 360 - d);
}

void main() {
  group('grain points', () {
    final pts = Atmosphere.grainPoints(
        seed: 7, count: Atmosphere.boardGrainDots, width: 15, height: 15);

    test('exactly count points, all inside the area', () {
      expect(pts, hasLength(Atmosphere.boardGrainDots));
      for (final p in pts) {
        expect(p.x, inInclusiveRange(0, 15));
        expect(p.y, inInclusiveRange(0, 15));
      }
    });

    test('deterministic for a seed, different for another', () {
      final again = Atmosphere.grainPoints(
          seed: 7, count: Atmosphere.boardGrainDots, width: 15, height: 15);
      final other = Atmosphere.grainPoints(
          seed: 8, count: Atmosphere.boardGrainDots, width: 15, height: 15);
      expect(again, pts);
      expect(other, isNot(pts));
    });

    test('evenly spread: no empty quadrant-of-quadrants, no clumps', () {
      // 4 x 4 blocks of 3.75 cells each hold about count / 16 points.
      final blocks = List<int>.filled(16, 0);
      for (final p in pts) {
        final c = math.min(3, (p.x / 3.75).floor());
        final r = math.min(3, (p.y / 3.75).floor());
        blocks[r * 4 + c]++;
      }
      final mean = pts.length / 16;
      for (final n in blocks) {
        expect(n, inInclusiveRange(mean * 0.7, mean * 1.3));
      }
    });

    test('a non-square area keeps its aspect', () {
      final wide =
          Atmosphere.grainPoints(seed: 1, count: 200, width: 40, height: 10);
      expect(wide, hasLength(200));
      expect(wide.every((p) => p.x <= 40 && p.y <= 10), isTrue);
      final left = wide.where((p) => p.x < 20).length;
      expect(left, inInclusiveRange(80, 120));
    });

    test('degenerate input gives no points', () {
      expect(Atmosphere.grainPoints(seed: 1, count: 0, width: 5, height: 5),
          isEmpty);
      expect(Atmosphere.grainPoints(seed: 1, count: 5, width: 0, height: 5),
          isEmpty);
    });
  });

  group('strength', () {
    test('High Contrast is calmer than the other palettes', () {
      expect(Atmosphere.strengthOf(PaletteId.classic), 1);
      expect(Atmosphere.strengthOf(PaletteId.slate), 1);
      expect(Atmosphere.strengthOf(PaletteId.highContrast), lessThan(0.5));
    });

    test('alpha scales and stays a valid alpha', () {
      expect(Atmosphere.alpha(0x40, 1), 0x40);
      expect(Atmosphere.alpha(0x40, 0), 0);
      expect(Atmosphere.alpha(0x40, 0.5), 0x20);
      expect(Atmosphere.alpha(0xFF, 3), 255);
      expect(Atmosphere.alpha(0x40, -1), 0);
    });

    test('every alpha at full strength stays subtle (at most 25%)', () {
      for (final a in [
        Atmosphere.boardGrainDarkAlpha,
        Atmosphere.boardGrainLightAlpha,
        Atmosphere.boardVignetteAlpha,
        Atmosphere.feltVignetteAlpha,
        Atmosphere.sheenAlpha,
      ]) {
        expect(a, lessThanOrEqualTo(64));
      }
      expect(Atmosphere.sheenStops,
          orderedEquals([...Atmosphere.sheenStops]..sort()));
      expect(Atmosphere.sheenStops.first, greaterThan(0));
      expect(Atmosphere.sheenStops.last, lessThan(1));
    });
  });

  group('Classic colours', () {
    final seats = PaletteSpec.classicLight.seat;
    const white = 0xFFFFFFFF;

    test('the yellow is warmer (a lower hue) than before, still yellow', () {
      expect(_hue(0xFFFFCB2B), lessThan(_hue(0xFFFDD835)));
      expect(_hue(seats[2]), inInclusiveRange(40, 55));
    });

    test('the green is lighter than before but still reads as green', () {
      expect(relativeLuminance(seats[1]),
          greaterThan(relativeLuminance(0xFF43A047)));
      expect(_hue(seats[1]), inInclusiveRange(110, 135));
    });

    test('all four seats keep at least 40 degrees of hue between them', () {
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          expect(_hueGap(seats[i], seats[j]), greaterThan(40),
              reason: 'seats $i and $j');
        }
      }
    });

    test('the lifted green still has 3:1 against the light cell', () {
      expect(contrastRatio(seats[1], white), greaterThanOrEqualTo(3.0));
    });

    test('the yellow is no paler against white than before', () {
      expect(contrastRatio(seats[2], white),
          greaterThan(contrastRatio(0xFFFDD835, white)));
    });

    test('both Classic variants share the seats (Classic only)', () {
      expect(PaletteSpec.classicDark.seat, seats);
      expect(PaletteSpec.slateLight.seat, isNot(seats));
      expect(PaletteSpec.highContrastLight.seat, isNot(seats));
    });
  });
}
