import 'package:ludo/ui/core/scaled_clock.dart';
import 'package:test/test.dart';

void main() {
  test('runs at the chosen speed', () {
    var base = 100.0;
    final clock = ScaledClock(() => base);
    expect(clock.now(), 0);
    base = 200;
    expect(clock.now(), 100);
    clock.speed = 4;
    base = 250;
    expect(clock.now(), 100 + 200);
  });

  test('a speed change does not make time jump or go back', () {
    var base = 0.0;
    final clock = ScaledClock(() => base, speed: 2);
    base = 50;
    clock.speed = 1;
    expect(clock.now(), 100);
    base = 80;
    expect(clock.now(), 130);
    clock.speed = 4;
    expect(clock.now(), 130);
  });

  test('time is monotonic while the base clock is', () {
    var base = 0.0;
    final clock = ScaledClock(() => base);
    var last = 0.0;
    for (var i = 1; i <= 50; i++) {
      base += 16.7;
      if (i % 10 == 0) {
        clock.speed = i % 20 == 0 ? 1 : 2;
      }
      final t = clock.now();
      expect(t, greaterThanOrEqualTo(last));
      last = t;
    }
  });
}
