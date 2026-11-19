import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/board_polish.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:test/test.dart';

void main() {
  const geo = BoardGeometry();

  test('cell gap is about 1.5 px and stays within its clamp', () {
    expect(BoardPolish.cellGap(25), closeTo(0.06, 1e-9));
    expect(BoardPolish.cellGap(1000), BoardPolish.minGap);
    expect(BoardPolish.cellGap(2), BoardPolish.maxGap);
    expect(BoardPolish.cellGap(0), BoardPolish.maxGap);
    // 1-2 px on every realistic phone and tablet cell size.
    for (final px in [18.0, 22.0, 26.0, 32.0, 40.0, 55.0]) {
      final gapPx = BoardPolish.cellGap(px) * px;
      expect(gapPx, inInclusiveRange(1.0, 2.0), reason: 'cell $px px');
    }
  });

  test('chevrons on start squares and home columns point at the centre', () {
    // Seat 0 start square (1, 6): walks right.
    expect(BoardPolish.towardCentre(geo.trackCell(0)), const Pt(1, 0));
    // Seat 1 start (8, 1): walks down.
    expect(BoardPolish.towardCentre(geo.trackCell(13)), const Pt(0, 1));
    // Seat 2 start (13, 8): walks left. Seat 3 start (6, 13): walks up.
    expect(BoardPolish.towardCentre(geo.trackCell(26)), const Pt(-1, 0));
    expect(BoardPolish.towardCentre(geo.trackCell(39)), const Pt(0, -1));
    // Every home-column cell points along its column, toward the centre.
    final expected = [
      const Pt(1, 0),
      const Pt(0, 1),
      const Pt(-1, 0),
      const Pt(0, -1),
    ];
    for (var seat = 0; seat < 4; seat++) {
      for (var p = firstHomeColumnPosition; p <= lastHomeColumnPosition; p++) {
        expect(
          BoardPolish.towardCentre(geo.homeCell(seat, p)),
          expected[seat],
          reason: 'seat $seat position $p',
        );
      }
    }
  });

  test('chevron turns match the direction and the chevron fits its tile', () {
    expect(BoardPolish.chevronTurns(geo.trackCell(0)), 0);
    expect(BoardPolish.chevronTurns(geo.trackCell(13)), 1);
    expect(BoardPolish.chevronTurns(geo.trackCell(26)), 2);
    expect(BoardPolish.chevronTurns(geo.trackCell(39)), 3);
    expect(BoardPolish.chevronReach, lessThan(0.4));
  });

  test('home pips sit in the seat\'s own centre triangle, evenly spaced', () {
    for (var seat = 0; seat < 4; seat++) {
      final pips = [for (var k = 0; k < 4; k++) BoardPolish.pipCentre(seat, k)];
      expect(pips.toSet().length, 4);
      for (var k = 1; k < 4; k++) {
        expect(
          pips[k].distanceTo(pips[k - 1]),
          closeTo(BoardPolish.pipSpacing, 1e-9),
        );
      }
      // The row is centred on the seat's axis through the board centre.
      final mid = Pt(
        pips.map((p) => p.x).reduce((a, b) => a + b) / 4,
        pips.map((p) => p.y).reduce((a, b) => a + b) / 4,
      );
      final axis = BoardGeometry.rotate(
        const Pt(6 + BoardPolish.pipDepth, 7.5),
        seat,
      );
      expect(mid.distanceTo(axis), lessThan(1e-9));
      // Inside the triangle, clear of the finished-token pocket (which
      // starts 0.45 cells from the base).
      for (final p in pips) {
        final local = _unrotate(p, seat);
        expect(local.x - 6, lessThan(0.45));
        // Width of the triangle at this depth holds the whole row.
        final halfWidth = 1.5 * (1 - (local.x - 6) / 1.5);
        expect((local.y - 7.5).abs() + BoardPolish.pipRadius,
            lessThanOrEqualTo(halfWidth));
      }
    }
  });

  test('home count counts only finished tokens', () {
    expect(BoardPolish.homeCount(const [-1, 12, 55, 56]), 1);
    expect(BoardPolish.homeCount(const [56, 56, 56, 56]), 4);
    expect(BoardPolish.homeCount(const [-1, -1, -1, -1]), 0);
  });

  test('dark marks go on light seat colours only', () {
    expect(BoardPolish.darkMarkOn(0.8), isTrue);
    expect(BoardPolish.darkMarkOn(0.1), isFalse);
  });
}

Pt _unrotate(Pt p, int seat) => BoardGeometry.rotate(p, (4 - seat) % 4);
