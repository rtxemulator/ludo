import 'dart:math' as math;

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

void main() {
  const geo = BoardGeometry();

  test('52 distinct track cells inside the 15 x 15 grid', () {
    final cells = {for (var s = 0; s < 52; s++) geo.trackCell(s)};
    expect(cells.length, 52);
    for (final c in cells) {
      expect(c.x, inInclusiveRange(0.5, 14.5));
      expect(c.y, inInclusiveRange(0.5, 14.5));
    }
  });

  test('consecutive squares are 1 cell apart, except 4 diagonal corners', () {
    // The path cuts diagonally around the 4 inner corners of the cross.
    const diagonal = {4, 17, 30, 43};
    for (var s = 0; s < 52; s++) {
      final d = geo.trackCell(s).distanceTo(geo.trackCell((s + 1) % 52));
      expect(d, closeTo(diagonal.contains(s) ? math.sqrt2 : 1, 1e-9),
          reason: 'square $s -> ${(s + 1) % 52}');
    }
  });

  test('start squares and star squares are where the board expects them', () {
    expect(geo.trackCell(0), const Pt(1.5, 6.5));
    expect(geo.trackCell(13), const Pt(8.5, 1.5));
    expect(geo.trackCell(26), const Pt(13.5, 8.5));
    expect(geo.trackCell(39), const Pt(6.5, 13.5));
    expect(geo.trackCell(8), const Pt(6.5, 2.5));
    expect(geo.trackCell(21), const Pt(12.5, 6.5));
    expect(geo.trackCell(34), const Pt(8.5, 12.5));
    expect(geo.trackCell(47), const Pt(2.5, 8.5));
  });

  test('every seat enters its home column right after its last track square',
      () {
    for (var seat = 0; seat < 4; seat++) {
      final last = geo.trackCell(absoluteSquare(seat, lastTrackPosition));
      expect(last.distanceTo(geo.homeCell(seat, firstHomeColumnPosition)),
          closeTo(1, 1e-9),
          reason: 'seat $seat');
      for (var p = firstHomeColumnPosition; p < lastHomeColumnPosition; p++) {
        expect(geo.homeCell(seat, p).distanceTo(geo.homeCell(seat, p + 1)),
            closeTo(1, 1e-9));
      }
    }
  });

  test('home columns never overlap the track or each other', () {
    final track = {for (var s = 0; s < 52; s++) geo.trackCell(s)};
    final seen = <Pt>{};
    for (var seat = 0; seat < 4; seat++) {
      for (var p = firstHomeColumnPosition; p <= lastHomeColumnPosition; p++) {
        final c = geo.homeCell(seat, p);
        expect(track.contains(c), isFalse);
        expect(seen.add(c), isTrue);
      }
    }
  });

  test('yard spots sit inside their own corner quadrant', () {
    for (var i = 0; i < 4; i++) {
      final s0 = geo.yardSpot(0, i);
      expect(s0.x, inExclusiveRange(0, 6));
      expect(s0.y, inExclusiveRange(0, 6));
      final s1 = geo.yardSpot(1, i);
      expect(s1.x, inExclusiveRange(9, 15));
      expect(s1.y, inExclusiveRange(0, 6));
      final s2 = geo.yardSpot(2, i);
      expect(s2.x, inExclusiveRange(9, 15));
      expect(s2.y, inExclusiveRange(9, 15));
      final s3 = geo.yardSpot(3, i);
      expect(s3.x, inExclusiveRange(0, 6));
      expect(s3.y, inExclusiveRange(9, 15));
    }
  });

  test('finish slots are inside the centre 3 x 3 and distinct', () {
    final slots = <Pt>{};
    for (var seat = 0; seat < 4; seat++) {
      for (var i = 0; i < 4; i++) {
        final p = geo.finishSlot(seat, i);
        expect(p.x, inInclusiveRange(6, 9));
        expect(p.y, inInclusiveRange(6, 9));
        expect(slots.add(p), isTrue);
      }
    }
  });

  test('stack offsets are distinct, centred and shrink the scale', () {
    expect(BoardGeometry.stackOffset(1, 0), Pt.zero);
    for (final n in [2, 3, 4, 5, 9, 16]) {
      final offsets = [
        for (var k = 0; k < n; k++) BoardGeometry.stackOffset(n, k)
      ];
      expect(offsets.toSet().length, n, reason: 'n=$n');
      final cx = offsets.map((o) => o.x).reduce((a, b) => a + b) / n;
      expect(cx.abs(), lessThan(1e-9), reason: 'n=$n x-centred');
      for (final o in offsets) {
        expect(o.x.abs(), lessThanOrEqualTo(0.5));
        expect(o.y.abs(), lessThanOrEqualTo(0.5));
      }
    }
    expect(BoardGeometry.stackScale(1), 1);
    expect(BoardGeometry.stackScale(3), 0.8);
    expect(BoardGeometry.stackScale(5), lessThan(0.8));
  });

  test('resting points: lone token sits on its cell centre', () {
    final state = makeState(tokens: {
      0: [5, -1, -1, -1],
    });
    final pts = geo.restingPoints(state);
    expect(pts[0][0], geo.trackCell(5));
    expect(pts[0][1], geo.yardSpot(0, 1));
  });

  test('resting points: tokens of different seats on a safe square split up',
      () {
    // Abs square 13 is seat 1's start (relative 0) and seat 0's relative 13.
    final state = makeState(tokens: {
      0: [13, -1, -1, -1],
      1: [0, -1, -1, -1],
    });
    final pts = geo.restingPoints(state);
    expect(pts[0][0], isNot(pts[1][0]));
    expect(pts[0][0].distanceTo(geo.trackCell(13)), lessThan(0.5));
    expect(pts[1][0].distanceTo(geo.trackCell(13)), lessThan(0.5));
    final scales = geo.restingScales(state);
    expect(scales[0][0], lessThan(1));
    expect(scales[1][0], lessThan(1));
    expect(scales[2][0], 1);
  });

  test('finished tokens rest in the pocket at pocket scale', () {
    final state = makeState(tokens: {
      2: [56, -1, -1, -1],
    });
    expect(geo.restingPoints(state)[2][0], geo.finishSlot(2, 0));
    expect(geo.restingScales(state)[2][0], 0.55);
  });
}
