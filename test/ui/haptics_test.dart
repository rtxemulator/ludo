import 'package:ludo/ui/core/haptics.dart';
import 'package:test/test.dart';

void main() {
  group('hapticPatterns', () {
    test('every event has a pattern', () {
      for (final event in HapticEvent.values) {
        expect(hapticPatterns[event], isNotEmpty, reason: '$event');
      }
    });

    test('strengths are in (0, 1] and gaps respect the minimum', () {
      for (final entry in hapticPatterns.entries) {
        final pulses = entry.value;
        for (var i = 0; i < pulses.length; i++) {
          expect(pulses[i].strength, inInclusiveRange(0.01, 1.0));
          expect(pulses[i].afterMs, greaterThanOrEqualTo(0));
          if (i > 0) {
            expect(pulses[i].afterMs, greaterThanOrEqualTo(hapticMinGapMs),
                reason: '${entry.key} pulse $i');
          }
        }
      }
    });

    test('dice impact: three ticks, 0.9 / 0.5 / 0.25, on the bounce times', () {
      final p = hapticPatterns[HapticEvent.diceImpact]!;
      expect(p.map((e) => e.kind), everyElement(HapticKind.tick));
      expect(p.map((e) => e.strength), [0.9, 0.5, 0.25]);
      // Impacts at 420, 650, 800 ms.
      expect(p[1].afterMs, 650 - 420);
      expect(p[2].afterMs, 800 - 650);
    });

    test('shapes from the table in the UI/UX doc', () {
      HapticKind kind(HapticEvent e, int i) => hapticPatterns[e]![i].kind;
      expect(kind(HapticEvent.diceSettle, 0), HapticKind.click);
      expect(kind(HapticEvent.tokenLand, 0), HapticKind.tick);
      expect(kind(HapticEvent.capture, 0), HapticKind.heavy);
      expect(kind(HapticEvent.capture, 1), HapticKind.click);
      expect(hapticPatterns[HapticEvent.home]!.map((e) => e.kind),
          [HapticKind.click, HapticKind.click, HapticKind.heavy]);
      expect(hapticPatterns[HapticEvent.home]!.map((e) => e.strength),
          orderedEquals([0.6, 0.8, 1.0]));
      expect(hapticPatterns[HapticEvent.illegal]!.length, 2);
      expect(hapticPatterns[HapticEvent.win]!.length, 5);
    });
  });

  group('HapticLimiter', () {
    test('blocks pulses closer than the minimum gap', () {
      final l = HapticLimiter();
      expect(l.tryAcquire(0), isTrue);
      expect(l.tryAcquire(10), isFalse);
      expect(l.tryAcquire(29.9), isFalse);
      expect(l.tryAcquire(30), isTrue);
      expect(l.tryAcquire(45), isFalse);
      expect(l.tryAcquire(60), isTrue);
    });

    test('a blocked pulse does not push the window forward', () {
      final l = HapticLimiter();
      expect(l.tryAcquire(100), isTrue);
      expect(l.tryAcquire(120), isFalse);
      expect(l.tryAcquire(131), isTrue);
    });

    test('reset forgets the last pulse', () {
      final l = HapticLimiter();
      l.tryAcquire(0);
      l.reset();
      expect(l.tryAcquire(1), isTrue);
    });
  });

  group('HapticPlayer', () {
    late double now;
    late List<(double, HapticPulse)> emitted;
    late List<(double, void Function())> queue;
    late HapticPlayer player;

    /// Runs scheduled actions in time order up to [until] ms from now.
    void advanceTo(double until) {
      queue.sort((a, b) => a.$1.compareTo(b.$1));
      while (queue.isNotEmpty && queue.first.$1 <= until) {
        final (at, action) = queue.removeAt(0);
        now = at;
        action();
      }
      now = until;
    }

    setUp(() {
      now = 0;
      emitted = [];
      queue = [];
      player = HapticPlayer(
        emit: (p) => emitted.add((now, p)),
        schedule: (delay, action) => queue.add((now + delay, action)),
        nowMs: () => now,
      );
    });

    test('plays the first pulse at once and schedules the rest', () {
      player.play(HapticEvent.capture);
      expect(emitted.length, 1);
      expect(emitted.single.$2.kind, HapticKind.heavy);
      advanceTo(500);
      expect(emitted.length, 2);
      expect(emitted[1].$1, 80);
      expect(emitted[1].$2.kind, HapticKind.click);
    });

    test('dice impact pulses land at 0, 230 and 380 ms', () {
      player.play(HapticEvent.diceImpact);
      advanceTo(1000);
      expect(emitted.map((e) => e.$1), [0, 230, 380]);
    });

    test('disabled: nothing is played, nothing is scheduled', () {
      player.enabled = false;
      player.play(HapticEvent.win);
      expect(emitted, isEmpty);
      expect(queue, isEmpty);
    });

    test('switching off mid-pattern stops the remaining pulses', () {
      player.play(HapticEvent.win);
      expect(emitted.length, 1);
      advanceTo(100);
      expect(emitted.length, 2);
      player.enabled = false;
      advanceTo(1000);
      expect(emitted.length, 2);
    });

    test('events fired in a burst are rate limited', () {
      player.play(HapticEvent.tokenLand);
      now = 10;
      player.play(HapticEvent.tokenLand);
      expect(emitted.length, 1);
      now = 40;
      player.play(HapticEvent.tokenLand);
      expect(emitted.length, 2);
    });

    test('six follows the settle click of the same roll', () {
      player.play(HapticEvent.diceSettle);
      player.play(HapticEvent.six);
      advanceTo(500);
      expect(emitted.map((e) => e.$1), [0, 80]);
    });
  });
}
