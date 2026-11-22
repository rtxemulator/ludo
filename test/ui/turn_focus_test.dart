import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/seat_plates.dart';
import 'package:ludo/ui/core/table_layout.dart';
import 'package:ludo/ui/core/turn_focus.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

const sizes = <(double, double)>[
  (360, 800),
  (411, 891),
  (390, 844),
  (360, 640),
  (320, 568),
  (800, 360),
  (600, 800),
  (768, 1024),
  (1024, 768),
  (1280, 800),
  (600, 600),
];

void main() {
  group('TurnFocus', () {
    const spec = MotionSpec.standard;

    test('a yard that is not on turn gets nothing and is not washed out', () {
      expect(TurnFocus.sample(500, 0, spec).visible, isFalse);
      expect(TurnFocus.inactiveWash, 0);
    });

    test('the ring breathes between its min and max and stays crisp', () {
      final bottom = TurnFocus.sample(0, 1, spec);
      final top = TurnFocus.sample(TurnFocus.periodMs / 2, 1, spec);
      expect(bottom.ringAlpha, closeTo(TurnFocus.ringAlphaMin, 1e-9));
      expect(top.ringAlpha, closeTo(TurnFocus.ringAlphaMax, 1e-9));
      expect(bottom.ringWidth, closeTo(TurnFocus.ringWidthMin, 1e-9));
      expect(top.ringWidth, closeTo(TurnFocus.ringWidthMax, 1e-9));
      // Always at least 60% opaque: a ring, not a haze.
      for (var t = 0.0; t < 2 * TurnFocus.periodMs; t += 37) {
        expect(
            TurnFocus.sample(t, 1, spec).ringAlpha, greaterThanOrEqualTo(0.6));
      }
    });

    test('the additive glow stays light', () {
      for (var t = 0.0; t < TurnFocus.periodMs; t += 50) {
        expect(
          TurnFocus.sample(t, 1, spec).glowAlpha,
          lessThanOrEqualTo(TurnFocus.glowAlphaMax),
        );
      }
    });

    test('the handoff scales the focus and reduced motion holds it steady', () {
      final half = TurnFocus.sample(0, 0.5, spec);
      final full = TurnFocus.sample(0, 1, spec);
      expect(half.ringAlpha, closeTo(full.ringAlpha / 2, 1e-9));
      final a = TurnFocus.sample(0, 1, MotionSpec.reduced);
      final b = TurnFocus.sample(900, 1, MotionSpec.reduced);
      expect(a.ringAlpha, b.ringAlpha);
      expect(a.ringWidth, b.ringWidth);
    });

    test('the ring lies inside the coloured border of the quadrant', () {
      // Quadrant edge 0, panel edge at 1 cell.
      expect(TurnFocus.ringCentre + TurnFocus.ringWidthMax / 2, lessThan(1));
      expect(TurnFocus.ringCentre - TurnFocus.ringWidthMax / 2, greaterThan(0));
      expect(
        TurnFocus.ringCentre + TurnFocus.glowWidth / 2,
        lessThanOrEqualTo(1),
      );
    });
  });

  group('SeatPlates', () {
    test('home count and label', () {
      final state = makeState(tokens: {
        0: [56, 56, 3, -1],
        1: [56, -1, -1, -1],
      });
      expect(SeatPlates.homeCount(state, 0), 2);
      expect(SeatPlates.homeCount(state, 1), 1);
      expect(SeatPlates.homeCount(state, 2), 0);
      expect(SeatPlates.homeLabel(2), '2/4');
    });

    test('a phone portrait gets four plates, facing their own edge', () {
      final layout = TableLayout.compute(width: 360, height: 800);
      final plates = SeatPlates.compute(layout);
      expect(plates.every((p) => p != null), isTrue);
      for (final p in plates) {
        expect(p!.edge, layout.edgeOf(p.seat));
        expect(p.depth,
            greaterThanOrEqualTo(SeatPlates.minDepthCells * layout.cell));
      }
    });

    for (final (w, h) in sizes) {
      test('plates at ${w.toInt()}x${h.toInt()} fit and collide with nothing',
          () {
        final layout = TableLayout.compute(width: w, height: h);
        final plates = SeatPlates.compute(layout);
        expect(plates, hasLength(4));
        final screen = Box(0, 0, w, h);
        for (var i = 0; i < 4; i++) {
          final p = plates[i];
          if (p == null) {
            continue;
          }
          expect(layout.placement, isNot(DockPlacement.inYard));
          expect(screen.containsBox(p.box), isTrue,
              reason: 'seat $i on screen');
          expect(p.box.overlaps(layout.frame), isFalse, reason: 'frame');
          expect(p.box.overlaps(layout.menu), isFalse, reason: 'menu');
          for (final dock in layout.docks) {
            expect(p.box.overlaps(dock.rect), isFalse, reason: 'dock');
            expect(p.box.overlaps(dock.tray), isFalse, reason: 'tray');
          }
          for (var j = i + 1; j < 4; j++) {
            final q = plates[j];
            if (q != null) {
              expect(p.box.overlaps(q.box), isFalse, reason: 'plates $i/$j');
            }
          }
        }
      });
    }

    test('docks inside the yards get no plates', () {
      for (final (w, h) in sizes) {
        final layout = TableLayout.compute(width: w, height: h);
        if (layout.placement == DockPlacement.inYard) {
          expect(SeatPlates.compute(layout).every((p) => p == null), isTrue);
        }
      }
    });
  });
}
