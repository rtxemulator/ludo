import 'dart:math' as math;

import 'package:ludo/ui/core/curves.dart';
import 'package:test/test.dart';

void main() {
  final eases = <String, Ease>{
    'linear': linear,
    'easeOutCubic': easeOutCubic,
    'easeInCubic': easeInCubic,
    'easeInOutCubic': easeInOutCubic,
    'easeInOutSine': easeInOutSine,
    'easeOutBack': easeOutBack,
    'cubicBezier(css ease)': cubicBezier(0.25, 0.1, 0.25, 1),
    'cubicBezier(0.2,0.8,0.2,1)': cubicBezier(0.2, 0.8, 0.2, 1),
  };

  eases.forEach((name, ease) {
    test('$name maps 0 to 0 and 1 to 1 and clamps', () {
      expect(ease(0), closeTo(0, 1e-9));
      expect(ease(1), closeTo(1, 1e-9));
      expect(ease(-3), closeTo(0, 1e-9));
      expect(ease(7), closeTo(1, 1e-9));
    });
  });

  for (final name in eases.keys.where((n) => n != 'easeOutBack')) {
    test('$name is monotonic', () {
      final ease = eases[name]!;
      var last = ease(0);
      for (var i = 1; i <= 200; i++) {
        final v = ease(i / 200);
        expect(v, greaterThanOrEqualTo(last - 1e-9), reason: 'at $i/200');
        last = v;
      }
    });
  }

  test('easeOutBack overshoots 1 before settling', () {
    final peak =
        List.generate(101, (i) => easeOutBack(i / 100)).reduce(math.max);
    expect(peak, greaterThan(1.05));
    expect(peak, lessThan(1.15));
  });

  test('cubicBezier(0,0,1,1) is linear', () {
    final ease = cubicBezier(0, 0, 1, 1);
    for (var i = 0; i <= 20; i++) {
      expect(ease(i / 20), closeTo(i / 20, 1e-5));
    }
  });

  test('arc is 0 at the ends and peaks at the height', () {
    expect(arc(0, 0.35), 0);
    expect(arc(1, 0.35), 0);
    expect(arc(0.5, 0.35), closeTo(0.35, 1e-12));
    expect(arc(-1, 0.35), 0);
    expect(arc(2, 0.35), 0);
  });

  test('dampedSine with integer cycles starts and ends at 0', () {
    expect(dampedSine(0, cycles: 5, decay: 5), closeTo(0, 1e-12));
    expect(dampedSine(1, cycles: 5, decay: 5), closeTo(0, 1e-9));
    expect(dampedSine(1, cycles: 2, decay: 6), closeTo(0, 1e-9));
  });

  test('dampedSine amplitude decays', () {
    double peak(double a, double b) => List.generate(
          101,
          (i) => dampedSine(a + (b - a) * i / 100, cycles: 5, decay: 5).abs(),
        ).reduce(math.max);
    expect(peak(0, 0.4), greaterThan(peak(0.6, 1)));
  });
}
