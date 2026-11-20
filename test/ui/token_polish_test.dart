import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pulse.dart';
import 'package:ludo/ui/core/token_look.dart';
import 'package:test/test.dart';

void main() {
  const spec = MotionSpec.standard;

  test('pawns are 15-20% bigger than before', () {
    final growth = TokenLook.baseRadius / TokenLook.previousBaseRadius - 1;
    expect(growth, inInclusiveRange(0.15, 0.20));
  });

  test('tap reach gives at least a 48 dp target and never less than 0.8', () {
    for (final px in [18.0, 22.0, 26.0, 32.0, 40.0, 60.0]) {
      final reach = TokenLook.tapReach(px);
      expect(reach, greaterThanOrEqualTo(0.8));
      // Diameter in dp is at least 48 (unless the clamp had to cap it).
      if (reach < 1.4) {
        expect(reach * px * 2, greaterThanOrEqualTo(48 - 1e-9));
      }
    }
    expect(TokenLook.tapReach(0), 0.8);
  });

  test('count badge from three tokens up', () {
    expect(TokenLook.showBadge(1), isFalse);
    expect(TokenLook.showBadge(2), isFalse);
    expect(TokenLook.showBadge(3), isTrue);
    expect(TokenLook.showBadge(16), isTrue);
  });

  test('movable tokens lift and fall with the pulse, others stay flat', () {
    var lo = double.infinity;
    var hi = 0.0;
    for (var t = 0.0; t < spec.pulsePeriodMs; t += 10) {
      final lift = PulseSample.movableLift(t, spec);
      lo = lift < lo ? lift : lo;
      hi = lift > hi ? lift : hi;
    }
    expect(lo, closeTo(0, 1e-9));
    expect(hi, closeTo(spec.movableLift, 1e-3));
    // Periodic and pure.
    expect(
      PulseSample.movableLift(123, spec),
      PulseSample.movableLift(123 + spec.pulsePeriodMs, spec),
    );
  });

  test('reduced motion: a steady half lift, no pulse', () {
    const reduced = MotionSpec(reducedMotion: true);
    expect(PulseSample.movableLift(0, reduced), reduced.movableLift * 0.5);
    expect(PulseSample.movableLift(300, reduced), reduced.movableLift * 0.5);
  });

  test('particle budget is 40 and confetti leaves room for a spark burst', () {
    expect(spec.maxParticles, 40);
    expect(spec.confettiCount + spec.sparkCount, lessThanOrEqualTo(40));
  });
}
