import 'package:ludo/ui/core/table_layout.dart';
import 'package:test/test.dart';

/// Phones, tablets, foldables, landscape and a square window.
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
  for (final (w, h) in sizes) {
    group('TableLayout ${w.toInt()}x${h.toInt()}', () {
      final layout = TableLayout.compute(width: w, height: h);
      final screen = Box(0, 0, w, h);

      test('the board is a square inside the screen with its frame', () {
        expect(layout.board.width, closeTo(layout.board.height, 1e-9));
        expect(layout.board.width, closeTo(15 * layout.cell, 1e-6));
        expect(layout.frame.width,
            closeTo(TableLayout.framedCells * layout.cell, 1e-6));
        expect(screen.containsBox(layout.frame), isTrue);
        expect(layout.frame.containsBox(layout.board), isTrue);
        expect(layout.cell, greaterThan(0));
      });

      test('the board is centred horizontally', () {
        expect(layout.frame.center.x, closeTo(w / 2, 1e-6));
      });

      test('docks and menu stay on screen', () {
        for (final d in layout.docks) {
          expect(screen.containsBox(d.rect), isTrue, reason: 'dock ${d.seat}');
        }
        expect(screen.containsBox(layout.menu), isTrue);
      });

      test('docks, menu and board frame never overlap (except in yards)', () {
        for (var i = 0; i < 4; i++) {
          final a = layout.docks[i];
          for (var j = i + 1; j < 4; j++) {
            expect(a.rect.overlaps(layout.docks[j].rect), isFalse,
                reason: 'docks $i and $j');
          }
          expect(a.rect.overlaps(layout.menu), isFalse, reason: 'dock $i menu');
          if (layout.placement != DockPlacement.inYard) {
            expect(a.rect.overlaps(layout.frame), isFalse,
                reason: 'dock $i frame');
          }
        }
        if (layout.placement == DockPlacement.inYard) {
          // Menu sits in its own strip above the board.
          expect(layout.menu.overlaps(layout.frame), isFalse);
        } else {
          expect(layout.menu.overlaps(layout.frame), isFalse);
        }
      });

      test('each die fits inside its dock zone', () {
        for (final d in layout.docks) {
          final die = Box.centered(d.dieCenter, d.dieSize, d.dieSize);
          expect(d.rect.containsBox(die), isTrue, reason: 'dock ${d.seat}');
          expect(d.dieSize, greaterThan(0));
        }
      });

      test('docks are next to their own yard corner', () {
        final centre = layout.board.center;
        for (final d in layout.docks) {
          final left = d.seat == 0 || d.seat == 3;
          final top = d.seat == 0 || d.seat == 1;
          expect(d.dieCenter.x < centre.x, left, reason: 'seat ${d.seat}');
          if (layout.placement == DockPlacement.topBottom) {
            expect(d.dieCenter.y < centre.y, top, reason: 'seat ${d.seat}');
          }
          if (layout.placement == DockPlacement.leftRight) {
            expect(d.dieCenter.y < centre.y, top, reason: 'seat ${d.seat}');
            expect(d.dieCenter.x < layout.board.left, left);
          }
        }
      });

      test('placement follows the larger margin pair', () {
        if (w < h && layout.placement != DockPlacement.inYard) {
          expect(layout.placement, DockPlacement.topBottom);
        }
        if (w > h && layout.placement != DockPlacement.inYard) {
          expect(layout.placement, DockPlacement.leftRight);
        }
      });

      test('every seat gets a table edge and Fixed mode is always upright', () {
        for (var seat = 0; seat < 4; seat++) {
          expect(SeatEdge.values, contains(layout.edgeOf(seat)));
          expect(seatTextTurns(layout, seat, UiOrientation.fixed), 0);
          expect(
            seatTextTurns(layout, seat, UiOrientation.table),
            turnsForEdge(layout.edgeOf(seat)),
          );
          for (var active = 0; active < 4; active++) {
            expect(
              sharedUiTurns(layout, active, UiOrientation.fixed),
              0,
            );
            expect(
              sharedUiTurns(layout, active, UiOrientation.table,
                  autoRotate: false),
              0,
            );
            expect(
              sharedUiTurns(layout, active, UiOrientation.table),
              seatTextTurns(layout, active, UiOrientation.table),
            );
          }
        }
      });
    });
  }

  group('phone portrait (360x800)', () {
    final layout = TableLayout.compute(width: 360, height: 800);

    test('docks are in the top and bottom margins', () {
      expect(layout.placement, DockPlacement.topBottom);
      expect(layout.docks[0].rect.bottom, lessThan(layout.frame.top));
      expect(layout.docks[1].rect.bottom, lessThan(layout.frame.top));
      expect(layout.docks[2].rect.top, greaterThan(layout.frame.bottom));
      expect(layout.docks[3].rect.top, greaterThan(layout.frame.bottom));
    });

    test('dock zone is 4.5 x 3.5 cells and the die is 1.9 cells', () {
      final d = layout.docks[0];
      expect(d.rect.width, closeTo(4.5 * layout.cell, 1e-6));
      expect(d.rect.height, closeTo(3.5 * layout.cell, 1e-6));
      expect(d.dieSize, closeTo(1.9 * layout.cell, 1e-6));
    });

    test('text turns: seats 0 and 1 face 180, seats 2 and 3 face 0', () {
      const t = UiOrientation.table;
      expect([for (var s = 0; s < 4; s++) seatTextTurns(layout, s, t)],
          [2, 2, 0, 0]);
      expect([for (var s = 0; s < 4; s++) layout.edgeOf(s)],
          [SeatEdge.top, SeatEdge.top, SeatEdge.bottom, SeatEdge.bottom]);
    });

    test('shared UI follows the active seat only in table mode', () {
      expect(sharedUiTurns(layout, 0, UiOrientation.table), 2);
      expect(sharedUiTurns(layout, 3, UiOrientation.table), 0);
      expect(sharedUiTurns(layout, 0, UiOrientation.fixed), 0);
    });

    test('the menu is top-centre', () {
      expect(layout.menu.center.x, closeTo(180, 1e-6));
      expect(layout.menu.center.y, lessThan(layout.frame.top));
    });
  });

  group('landscape (800x360)', () {
    final layout = TableLayout.compute(width: 800, height: 360);

    test('docks move to the left and right margins', () {
      expect(layout.placement, DockPlacement.leftRight);
      expect(layout.docks[0].rect.right, lessThan(layout.frame.left));
      expect(layout.docks[3].rect.right, lessThan(layout.frame.left));
      expect(layout.docks[1].rect.left, greaterThan(layout.frame.right));
      expect(layout.docks[2].rect.left, greaterThan(layout.frame.right));
    });

    test('text turns: left seats 90, right seats 270 clockwise', () {
      const t = UiOrientation.table;
      expect([for (var s = 0; s < 4; s++) seatTextTurns(layout, s, t)],
          [1, 3, 3, 1]);
    });
  });

  group('tablets keep docks in the margins by shrinking the board a little',
      () {
    test('768x1024 portrait and 1024x768 landscape', () {
      final portrait = TableLayout.compute(width: 768, height: 1024);
      expect(portrait.placement, DockPlacement.topBottom);
      final landscape = TableLayout.compute(width: 1024, height: 768);
      expect(landscape.placement, DockPlacement.leftRight);
      // The board is at most 10% smaller than the width-filling size.
      final full = (768 - 16) / TableLayout.framedCells;
      expect(portrait.cell, greaterThanOrEqualTo(0.9 * full));
    });
  });

  group('square window (600x600)', () {
    test('docks fall back to the yards and the menu gets its own strip', () {
      final layout = TableLayout.compute(width: 600, height: 600);
      expect(layout.placement, DockPlacement.inYard);
      for (var seat = 0; seat < 4; seat++) {
        expect(layout.frame.containsBox(layout.docks[seat].rect), isTrue);
      }
      expect(layout.menu.bottom, lessThanOrEqualTo(layout.frame.top));
    });
  });

  test('turnsForEdge covers all edges', () {
    expect(turnsForEdge(SeatEdge.bottom), 0);
    expect(turnsForEdge(SeatEdge.left), 1);
    expect(turnsForEdge(SeatEdge.top), 2);
    expect(turnsForEdge(SeatEdge.right), 3);
  });
}
