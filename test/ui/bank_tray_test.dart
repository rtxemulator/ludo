import 'package:ludo/ui/core/bank_tray.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:test/test.dart';

const _spec = MotionSpec.standard;

BankTray _tray(List<int> values, {int seat = 0, double now = 0}) {
  final tray = BankTray();
  for (final v in values) {
    tray.append(seat, v, now);
  }
  return tray;
}

/// Pose of present chip [i] of [seat] at [now].
ChipPose _at(BankTray tray, int seat, int i, double now,
        [MotionSpec spec = _spec]) =>
    tray.pose(tray.presentOf(seat)[i], now, spec)!;

void main() {
  group('fan layout', () {
    test('one chip sits in the middle, two are symmetric', () {
      expect(fanX(0, 1, 5), 0);
      expect(fanX(0, 2, 5), closeTo(-fanX(1, 2, 5), 1e-12));
      expect(fanX(1, 2, 5) - fanX(0, 2, 5), closeTo(1.12, 1e-12));
    });

    test('a full tray squeezes the chips instead of overflowing', () {
      const capacity = 5.5;
      for (var n = 1; n <= 14; n++) {
        final first = fanX(0, n, capacity);
        final last = fanX(n - 1, n, capacity);
        // Outer edges of the outer chips stay inside the tray.
        expect(last + 0.5, lessThanOrEqualTo(capacity / 2 + 1e-9),
            reason: 'n=$n');
        expect(first - 0.5, greaterThanOrEqualTo(-capacity / 2 - 1e-9));
        // Order is preserved.
        for (var i = 1; i < n; i++) {
          expect(fanX(i, n, capacity), greaterThan(fanX(i - 1, n, capacity)));
        }
      }
    });

    test('tilt is symmetric and capped, the middle chip is straight', () {
      expect(fanAngle(1, 3, _spec), 0);
      expect(fanAngle(0, 3, _spec), closeTo(-fanAngle(2, 3, _spec), 1e-12));
      expect(fanAngle(0, 40, _spec).abs(), _spec.tray.fanMaxTilt);
      expect(fanY(1, 3, _spec), 0);
      expect(fanY(0, 3, _spec), greaterThan(0));
    });

    test('hitChip picks the nearest chip, the topmost on a tie', () {
      expect(hitChip(0, 0, 5), -1);
      expect(hitChip(3, 1, 5), 0);
      const n = 3;
      for (var i = 0; i < n; i++) {
        expect(hitChip(fanX(i, n, 5.5) + 0.05, n, 5.5), i);
      }
      // A tap far from every chip hits nothing when a slop is given.
      expect(hitChip(3, 2, 5, slop: 0.9), -1);
      expect(hitChip(fanX(1, 2, 5) + 0.8, 2, 5, slop: 0.9), 1);
      // Exactly between two chips: the later one is on top.
      final mid = (fanX(0, 2, 5) + fanX(1, 2, 5)) / 2;
      expect(hitChip(mid, 2, 5), 1);
    });
  });

  group('appending and sliding', () {
    test('values keep the rolled order and are per seat', () {
      final tray = _tray([6, 6, 2]);
      tray.append(2, 5, 0);
      expect(tray.valuesOf(0), [6, 6, 2]);
      expect(tray.valuesOf(2), [5]);
      expect(tray.valuesOf(1), isEmpty);
    });

    test('a new chip pops in; the others glide to make room', () {
      final tray = _tray([6], now: 0);
      final before = _at(tray, 0, 0, 1000).x;
      expect(before, 0);
      tray.append(0, 3, 1000);

      // The newcomer starts small and transparent, then settles at 1.
      final born = _at(tray, 0, 1, 1000);
      expect(born.scale, closeTo(_spec.tray.popFromScale, 1e-9));
      expect(born.opacity, 0);
      final done = _at(tray, 0, 1, 1000 + _spec.tray.popMs);
      expect(done.scale, closeTo(1, 1e-9));
      expect(done.opacity, 1);

      // The old chip starts where it was and ends at its fan slot.
      expect(_at(tray, 0, 0, 1000).x, closeTo(0, 1e-9));
      final slot = fanX(0, 2, tray.capacity[0]);
      expect(_at(tray, 0, 0, 1000 + _spec.tray.slideMs).x, closeTo(slot, 1e-9));
      final mid = _at(tray, 0, 0, 1000 + _spec.tray.slideMs / 2).x;
      expect(mid, lessThan(0));
      expect(mid, greaterThan(slot));
    });

    test('a narrower tray re-lays the chips out', () {
      final tray = _tray([1, 2, 3, 4, 5, 6, 1, 2]);
      final wide = _at(tray, 0, 7, 5000).x;
      tray.setCapacity(0, 3, 5000);
      expect(_at(tray, 0, 7, 5000 + _spec.tray.slideMs).x, lessThan(wide));
    });
  });

  group('spending', () {
    test('the spent chip flies to the token, shrinks and dissolves', () {
      final tray = _tray([3, 5, 1]);
      tray.spendAt(0, 1, const Pt(4, 9), 1000);
      // It is no longer part of the bank.
      expect(tray.valuesOf(0), [3, 1]);

      final start = tray.chips.firstWhere((c) => c.leaving);
      ChipPose? at(double dt) => tray.pose(start, 1000 + dt, _spec);

      final p0 = at(0)!;
      expect(p0.flight, 0);
      expect(p0.opacity, 1);
      expect(p0.target, const Pt(4, 9));

      var last = 0.0;
      for (var dt = 0.0; dt <= _spec.tray.spendMs - 1; dt += 20) {
        final p = at(dt)!;
        expect(p.flight, greaterThanOrEqualTo(last));
        last = p.flight;
      }
      final nearEnd = at(_spec.tray.spendMs - 1)!;
      expect(nearEnd.flight, closeTo(1, 0.01));
      expect(nearEnd.opacity, lessThan(0.05));
      expect(at(_spec.tray.spendMs), isNull);
    });

    test('a selected chip leaves from its lifted size', () {
      final tray = _tray([3, 5]);
      tray.select(0, 1, 0);
      tray.spendAt(0, 1, const Pt(1, 1), 1000);
      final chip = tray.chips.firstWhere((c) => c.leaving);
      final p = tray.pose(chip, 1000, _spec)!;
      expect(p.scale, closeTo(_spec.tray.selectedScale, 1e-9));
    });

    test('prune removes a spent chip only once it is gone', () {
      final tray = _tray([3, 5]);
      tray.spendAt(0, 0, const Pt(1, 1), 1000);
      expect(tray.chips, hasLength(2));
      tray.prune(1000 + _spec.tray.spendMs - 1, _spec);
      expect(tray.chips, hasLength(2));
      tray.prune(1000 + _spec.tray.spendMs, _spec);
      expect(tray.chips, hasLength(1));
      expect(tray.valuesOf(0), [5]);
    });

    test('reduced motion fades in place instead of flying', () {
      const reduced = MotionSpec.reduced;
      final tray = _tray([3, 5]);
      tray.spendAt(0, 0, const Pt(1, 1), 1000);
      final chip = tray.chips.firstWhere((c) => c.leaving);
      final mid = tray.pose(chip, 1000 + reduced.reducedFadeMs / 2, reduced)!;
      expect(mid.flight, 0);
      expect(mid.opacity, closeTo(0.5, 1e-9));
      expect(tray.pose(chip, 1000 + reduced.reducedFadeMs, reduced), isNull);
    });
  });

  group('wipe and revert', () {
    test('a wipe bursts the whole bank, one chip after the other', () {
      final tray = _tray([6, 6, 4]);
      tray.exitAll(0, ChipExit.wipe, 1000);
      expect(tray.valuesOf(0), isEmpty);
      final chips = tray.chips.toList();
      final last = chips.last;
      final total = tray.exitTotalMs(last, _spec);
      expect(total, 2 * _spec.tray.wipeStaggerMs + _spec.tray.wipeMs);

      // Chips die in order; the last one is still drawn when the first is gone.
      final firstGone = 1000 + _spec.tray.wipeMs;
      expect(tray.pose(chips.first, firstGone, _spec), isNull);
      expect(tray.pose(last, firstGone, _spec), isNotNull);

      // Burst: it grows while it fades.
      final burst = tray.pose(
        chips.first,
        1000 + _spec.tray.wipeMs * 0.95,
        _spec,
      )!;
      expect(burst.scale, greaterThan(1));
      expect(burst.opacity, lessThan(0.3));

      tray.prune(1000 + total, _spec);
      expect(tray.isEmpty, isTrue);
    });

    test('a delayed exit holds the chips still until it starts', () {
      final tray = _tray([2, 5]);
      tray.exitAll(0, ChipExit.revert, 1000, delayMs: 260);
      expect(tray.valuesOf(0), isEmpty);
      final chip = tray.chips.first;
      final held = tray.pose(chip, 1100, _spec)!;
      expect(held.scale, 1);
      expect(held.opacity, 1);
      final going = tray.pose(chip, 1260 + _spec.tray.revertMs / 2, _spec)!;
      expect(going.opacity, closeTo(0.5, 1e-9));
      // Pruning waits for the delay too.
      tray.prune(1000 + _spec.tray.revertMs, _spec);
      expect(tray.chips, isNotEmpty);
      tray.prune(1260 + 30 + _spec.tray.revertMs, _spec); // last chip's stagger
      expect(tray.isEmpty, isTrue);
    });

    test('a revert shrinks and fades the bank away', () {
      final tray = _tray([2, 5]);
      tray.exitAll(0, ChipExit.revert, 0);
      final chip = tray.chips.first;
      final mid = tray.pose(chip, _spec.tray.revertMs / 2, _spec)!;
      expect(mid.scale, lessThan(1));
      expect(mid.opacity, closeTo(0.5, 1e-9));
      expect(tray.pose(chip, _spec.tray.revertMs, _spec), isNull);
    });
  });

  group('selection, prompt and shake', () {
    test('selecting lifts the chip, deselecting puts it back', () {
      final tray = _tray([3, 5]);
      expect(tray.selectedIndex(0), isNull);
      tray.select(0, 1, 1000);
      expect(tray.selectedIndex(0), 1);
      expect(_at(tray, 0, 1, 1000).select, 0);
      final up = _at(tray, 0, 1, 1000 + _spec.tray.selectMs);
      expect(up.select, closeTo(1, 1e-9));
      expect(up.scale, closeTo(_spec.tray.selectedScale, 1e-9));
      expect(_at(tray, 0, 0, 2000).select, 0);

      // Moving the selection lowers the old chip.
      tray.select(0, 0, 3000);
      expect(tray.selectedIndex(0), 0);
      expect(
          _at(tray, 0, 1, 3000 + _spec.tray.selectMs).select, closeTo(0, 1e-9));
      tray.select(0, null, 4000);
      expect(tray.selectedIndex(0), isNull);
    });

    test('the prompt swells every chip once and settles', () {
      final tray = _tray([3, 5]);
      final calm = _at(tray, 0, 0, 5000).scale;
      tray.prompt(0, 5000);
      final swell = _at(tray, 0, 0, 5000 + _spec.tray.promptMs / 2).scale;
      expect(swell, closeTo(calm * (1 + _spec.tray.promptScale), 1e-9));
      expect(_at(tray, 0, 0, 5000 + _spec.tray.promptMs).scale,
          closeTo(calm, 1e-9));
    });

    test('the shake moves the tray sideways and returns to rest', () {
      final tray = _tray([3, 5]);
      final rest = _at(tray, 0, 0, 5000).x;
      tray.shake(0, 5000);
      var moved = false;
      for (var dt = 10.0; dt < _spec.tray.shakeMs; dt += 10) {
        if ((_at(tray, 0, 0, 5000 + dt).x - rest).abs() > 0.01) {
          moved = true;
        }
      }
      expect(moved, isTrue);
      expect(_at(tray, 0, 0, 5000 + _spec.tray.shakeMs).x, closeTo(rest, 1e-9));
    });

    test('reduced motion switches shake and swell off', () {
      const reduced = MotionSpec.reduced;
      final tray = _tray([3, 5]);
      tray.shake(0, 5000);
      tray.prompt(0, 5000);
      expect(tray.shakeOffset(0, 5050, reduced), 0);
      expect(tray.promptSwell(0, 5050, reduced), 0);
    });
  });

  group('reconcile and clear', () {
    test('reconcile is a no-op when the chips already match the bank', () {
      final tray = _tray([6, 2]);
      final ids = [for (final c in tray.presentOf(0)) c.id];
      tray.reconcile(0, [6, 2], 100);
      expect([for (final c in tray.presentOf(0)) c.id], ids);
    });

    test('reconcile repairs a mismatch silently (no pop)', () {
      final tray = _tray([6, 2]);
      tray.reconcile(0, [4, 4, 1], 10000);
      expect(tray.valuesOf(0), [4, 4, 1]);
      for (var i = 0; i < 3; i++) {
        final p = _at(tray, 0, i, 10000);
        expect(p.scale, closeTo(1, 1e-9));
        expect(p.opacity, 1);
      }
    });

    test('clear drops everything', () {
      final tray = _tray([6, 2]);
      tray.exitAll(0, ChipExit.wipe, 0);
      tray.clear();
      expect(tray.isEmpty, isTrue);
    });
  });

  test('poses are pure functions of time', () {
    final a = _tray([6, 3, 5])..select(0, 2, 100);
    final b = _tray([6, 3, 5])..select(0, 2, 100);
    for (var t = 0.0; t < 800; t += 37) {
      for (var i = 0; i < 3; i++) {
        final pa = _at(a, 0, i, t);
        final pb = _at(b, 0, i, t);
        expect(pa.x, pb.x);
        expect(pa.scale, pb.scale);
        expect(pa.opacity, pb.opacity);
      }
    }
  });
}
