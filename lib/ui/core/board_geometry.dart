/// Where everything sits on the 15 x 15 board grid. Pure Dart, no Flutter.
///
/// Seat 0 is the top-left yard and seats run clockwise. Coordinates are in
/// grid units: cell `(col, row)` has its centre at `(col + 0.5, row + 0.5)`.
library;

import 'dart:math' as math;

import 'package:ludo/engine/ludo_engine.dart';

import 'pt.dart';

/// Geometry of the standard Ludo board for the engine's coordinate system.
class BoardGeometry {
  const BoardGeometry();

  /// Board width/height in cells.
  static const int gridSize = 15;

  /// Absolute squares `0..12` (the rest are quarter turns of these).
  static const List<(int, int)> _baseTrack = [
    (1, 6), (2, 6), (3, 6), (4, 6), (5, 6), // seat 0 start + along the row
    (6, 5), (6, 4), (6, 3), (6, 2), (6, 1), (6, 0), // up the column
    (7, 0), (8, 0), // across the top
  ];

  static const List<Pt> _baseYard = [Pt(2, 2), Pt(4, 2), Pt(2, 4), Pt(4, 4)];

  /// Rotates [p] by [quarterTurns] clockwise around the board centre.
  static Pt rotate(Pt p, int quarterTurns) {
    var r = p;
    for (var i = 0; i < quarterTurns % 4; i++) {
      r = Pt(gridSize - r.y, r.x);
    }
    return r;
  }

  static Pt _cell(int col, int row) => Pt(col + 0.5, row + 0.5);

  /// Centre of absolute track square [square] (`0..51`).
  Pt trackCell(int square) {
    assert(square >= 0 && square < trackSquares, 'bad square $square');
    final (col, row) = _baseTrack[square % seatTrackOffset];
    return rotate(_cell(col, row), square ~/ seatTrackOffset);
  }

  /// Centre of home-column cell [position] (`51..55`, relative) of [seat].
  Pt homeCell(int seat, int position) {
    assert(isInHomeColumn(position), 'bad home position $position');
    return rotate(_cell(position - firstHomeColumnPosition + 1, 7), seat);
  }

  /// Yard spot of token [tokenIndex] of [seat].
  Pt yardSpot(int seat, int tokenIndex) => rotate(_baseYard[tokenIndex], seat);

  /// Pocket slot a finished token rests in (centre 3 x 3, toward its seat).
  Pt finishSlot(int seat, int tokenIndex) => rotate(
        Pt(6.7, 7.5 + (tokenIndex - 1.5) * 0.34),
        seat,
      );

  /// Cell centre for a *relative* [position] of [seat], ignoring stacking.
  ///
  /// `-1` yard, `0..50` track, `51..55` home column, `56` finished.
  Pt cellCenter(int seat, int position, int tokenIndex) {
    if (position == yardPosition) {
      return yardSpot(seat, tokenIndex);
    }
    if (isOnTrack(position)) {
      return trackCell(absoluteSquare(seat, position));
    }
    if (isInHomeColumn(position)) {
      return homeCell(seat, position);
    }
    return finishSlot(seat, tokenIndex);
  }

  /// Offset of the [k]-th of [n] tokens sharing one cell.
  static Pt stackOffset(int n, int k) {
    assert(n >= 1 && k >= 0 && k < n);
    if (n == 1) {
      return Pt.zero;
    }
    final cols = math.sqrt(n).ceil();
    final rows = (n / cols).ceil();
    final spacing = 0.8 / cols;
    final row = k ~/ cols;
    final inLastRow = row == rows - 1 ? n - row * cols : cols;
    final col = k - row * cols;
    return Pt(
      (col - (inLastRow - 1) / 2) * spacing,
      (row - (rows - 1) / 2) * spacing,
    );
  }

  /// Token scale when [n] tokens share a cell.
  static double stackScale(int n) {
    if (n <= 1) {
      return 1;
    }
    return math.sqrt(n).ceil() == 2 ? 0.8 : 0.62;
  }

  /// Resting point of every token (`[seat][token]`), with stacking offsets
  /// for tokens that share a track or home-column cell.
  List<List<Pt>> restingPoints(GameState state) {
    final groups = <String, List<(int, int)>>{};
    for (var seat = 0; seat < seatCount; seat++) {
      for (var i = 0; i < tokensPerSeat; i++) {
        final position = state.tokens[seat][i];
        final key = isOnTrack(position)
            ? 'T${absoluteSquare(seat, position)}'
            : isInHomeColumn(position)
                ? 'H$seat:$position'
                : null;
        if (key != null) {
          (groups[key] ??= []).add((seat, i));
        }
      }
    }
    final points = [
      for (var seat = 0; seat < seatCount; seat++)
        [
          for (var i = 0; i < tokensPerSeat; i++)
            cellCenter(seat, state.tokens[seat][i], i),
        ],
    ];
    for (final group in groups.values) {
      for (var k = 0; k < group.length; k++) {
        final (seat, i) = group[k];
        points[seat][i] = points[seat][i] + stackOffset(group.length, k);
      }
    }
    return points;
  }

  /// Token scale for each token of [state] (`[seat][token]`).
  List<List<double>> restingScales(GameState state) {
    final counts = <String, int>{};
    String? keyOf(int seat, int position) => isOnTrack(position)
        ? 'T${absoluteSquare(seat, position)}'
        : isInHomeColumn(position)
            ? 'H$seat:$position'
            : null;
    for (var seat = 0; seat < seatCount; seat++) {
      for (final position in state.tokens[seat]) {
        final key = keyOf(seat, position);
        if (key != null) {
          counts[key] = (counts[key] ?? 0) + 1;
        }
      }
    }
    return [
      for (var seat = 0; seat < seatCount; seat++)
        [
          for (final position in state.tokens[seat])
            () {
              final key = keyOf(seat, position);
              if (key == null) {
                return position == finishPosition ? 0.55 : 1.0;
              }
              return stackScale(counts[key]!);
            }(),
        ],
    ];
  }
}
