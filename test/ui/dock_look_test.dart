import 'package:ludo/ui/core/dock_look.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/table_layout.dart';
import 'package:test/test.dart';

void main() {
  const spec = MotionSpec.standard;

  group('DockLook.live', () {
    test('the seat that becomes active rises 0 -> 1 in 200 ms', () {
      double live(double t) =>
          DockLook.live(active: true, wasActive: false, sinceMs: t);
      expect(live(0), 0);
      expect(live(spec.dockHandoffMs), closeTo(1, 1e-9));
      expect(live(5000), 1);
      var last = -1.0;
      for (var t = 0.0; t <= 200; t += 10) {
        expect(live(t), greaterThanOrEqualTo(last));
        last = live(t);
      }
    });

    test('the seat that stops being active falls 1 -> 0; others stay 0', () {
      expect(DockLook.live(active: false, wasActive: true, sinceMs: 0), 1);
      expect(
        DockLook.live(active: false, wasActive: true, sinceMs: 200),
        closeTo(0, 1e-9),
      );
      expect(DockLook.live(active: false, wasActive: false, sinceMs: 50), 0);
    });

    test('reduced motion switches at once', () {
      expect(
        DockLook.live(
          active: true,
          wasActive: false,
          sinceMs: 0,
          spec: MotionSpec.reduced,
        ),
        1,
      );
    });
  });

  group('DockLook.sample', () {
    test('ghost: 45% opacity, 0.8 scale, desaturated, no halo', () {
      final look = DockLook.sample(live: 0, idle: false, tMs: 123);
      expect(look.opacity, closeTo(0.45, 1e-9));
      expect(look.scale, closeTo(0.8, 1e-9));
      expect(look.desaturate, closeTo(spec.ghostDesaturate, 1e-9));
      expect(look.halo, 0);
    });

    test('live and not idle: full size, no bob, no halo', () {
      for (var t = 0.0; t < 3200; t += 100) {
        final look = DockLook.sample(live: 1, idle: false, tMs: t);
        expect(look.opacity, 1);
        expect(look.scale, 1);
        expect(look.desaturate, 0);
        expect(look.halo, 0);
      }
    });

    test('idle bob stays within +-4% and loops every 1.6 s', () {
      for (var t = 0.0; t < 3200; t += 25) {
        final look = DockLook.sample(live: 1, idle: true, tMs: t);
        expect(look.scale, inInclusiveRange(0.96 - 1e-9, 1.04 + 1e-9));
        expect(look.halo, greaterThan(0));
        final again = DockLook.sample(
          live: 1,
          idle: true,
          tMs: t + spec.idleBobPeriodMs,
        );
        expect(again.scale, closeTo(look.scale, 1e-9));
      }
    });

    test('idle in reduced motion has a steady halo and no bob', () {
      for (var t = 0.0; t < 2000; t += 100) {
        final look = DockLook.sample(
          live: 1,
          idle: true,
          tMs: t,
          spec: MotionSpec.reduced,
        );
        expect(look.scale, 1);
        expect(look.halo, closeTo(MotionSpec.reduced.idleHaloOpacity, 1e-9));
      }
    });
  });

  group('DockLook.pulse', () {
    test('fades 1 -> 0 over 300 ms, 0 outside', () {
      expect(DockLook.pulse(99, 100, spec), 0);
      expect(DockLook.pulse(100, 100, spec), 1);
      expect(DockLook.pulse(250, 100, spec), closeTo(0.5, 1e-9));
      expect(DockLook.pulse(400, 100, spec), 0);
      expect(DockLook.pulse(150, 100, MotionSpec.reduced), 0);
    });
  });

  group('rotateQuarterTurns', () {
    test('one turn clockwise: down -> left -> up -> right -> down', () {
      const down = Pt(0, 1);
      expect(rotateQuarterTurns(down, 1), const Pt(-1, 0));
      expect(rotateQuarterTurns(down, 2), const Pt(0, -1));
      expect(rotateQuarterTurns(down, 3), const Pt(1, 0));
      expect(rotateQuarterTurns(down, 4), down);
      expect(rotateQuarterTurns(down, -1), const Pt(1, 0));
    });

    test("a dock's local +y points at its own table edge, in every layout", () {
      const toward = {
        SeatEdge.bottom: Pt(0, 1),
        SeatEdge.left: Pt(-1, 0),
        SeatEdge.top: Pt(0, -1),
        SeatEdge.right: Pt(1, 0),
      };
      for (final size in const [
        (400.0, 850.0),
        (850.0, 400.0),
        (900.0, 920.0),
      ]) {
        final layout = TableLayout.compute(width: size.$1, height: size.$2);
        for (final dock in layout.docks) {
          final v = rotateQuarterTurns(const Pt(0, 1), turnsForEdge(dock.edge));
          final want = toward[dock.edge]!;
          expect(v.x, closeTo(want.x, 1e-9));
          expect(v.y, closeTo(want.y, 1e-9));
        }
      }
    });
  });
}
