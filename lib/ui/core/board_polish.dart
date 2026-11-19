/// Numbers and small helpers for the static board polish (cell gaps, bevel,
/// chevrons, inset yards) and for the dynamic "tokens home" pips in the
/// centre. Pure Dart, no Flutter: the painters only draw what is decided here
/// and the tests pin it down.
library;

import 'dart:math' as math;

import 'board_geometry.dart';
import 'pt.dart';

/// Look constants of the board (grid units, 1 = one cell).
class BoardPolish {
  const BoardPolish._();

  /// Target gap between two neighbouring cells, in logical pixels.
  static const double gapPx = 1.5;

  /// The gap never gets thinner or wider than this (cells), so it stays a
  /// hairline on tablets and does not eat the cells on tiny screens.
  static const double minGap = 0.03;
  static const double maxGap = 0.10;

  /// Corner radius of a cell tile.
  static const double cellRadius = 0.09;

  /// Distance of the faint inner bevel line from the tile edge, and its width.
  static const double bevelInset = 0.07;
  static const double bevelWidth = 0.035;

  /// How much the bevel line is lightened and the tile edge darkened
  /// (symmetric: one overhead light, no lit corner).
  static const double bevelLighten = 0.22;
  static const double bevelDarken = 0.10;

  /// Chevron: half width (across the walking direction), half length, stroke.
  static const double chevronHalfWidth = 0.2;
  static const double chevronHalfLength = 0.13;
  static const double chevronStroke = 0.085;

  /// The yard's inner panel is inset by this much from the coloured quadrant
  /// (the quadrant itself stays flush with the path arms), with a symmetric
  /// recess line just inside the panel edge.
  static const double yardInset = 1.0;
  static const double yardRecessWidth = 0.06;

  /// Radius of the ring that marks a token's yard spot (a token is 0.45).
  static const double yardSpotRadius = 0.56;

  /// Home pips: one per token of a seat, in the centre triangle.
  static const double pipRadius = 0.12;
  static const double pipSpacing = 0.4;

  /// Depth of the pip row from the triangle's base (the line next to the
  /// home column), in cells.
  static const double pipDepth = 0.28;

  /// Gap between neighbouring cells for a board drawn with [cellPx] logical
  /// pixels per cell: about [gapPx] pixels, within [minGap]..[maxGap].
  static double cellGap(double cellPx) {
    if (cellPx <= 0) {
      return maxGap;
    }
    return (gapPx / cellPx).clamp(minGap, maxGap);
  }

  /// Unit axis (one of `(+-1, 0)`, `(0, +-1)`) from [cell] toward the board
  /// centre: the direction a chevron on a start square or a home-column cell
  /// points.
  static Pt towardCentre(Pt cell) {
    const c = BoardGeometry.gridSize / 2;
    final dx = c - cell.x;
    final dy = c - cell.y;
    if (dx.abs() >= dy.abs()) {
      return Pt(dx < 0 ? -1 : 1, 0);
    }
    return Pt(0, dy < 0 ? -1 : 1);
  }

  /// Quarter turns clockwise (0..3) that take "pointing right" to
  /// [towardCentre] of [cell].
  static int chevronTurns(Pt cell) {
    final d = towardCentre(cell);
    if (d.x > 0) {
      return 0;
    }
    if (d.y > 0) {
      return 1;
    }
    if (d.x < 0) {
      return 2;
    }
    return 3;
  }

  /// Centre of pip [slot] (`0..3`) of [seat]'s centre triangle.
  static Pt pipCentre(int seat, int slot) {
    assert(slot >= 0 && slot < 4);
    return BoardGeometry.rotate(
      Pt(6 + pipDepth, 7.5 + (slot - 1.5) * pipSpacing),
      seat,
    );
  }

  /// Number of tokens of one seat that reached the finish square, from the
  /// token positions (`56` = finished).
  static int homeCount(Iterable<int> positions) =>
      positions.where((p) => p == 56).length;

  /// Seat-colour luminance above which a mark drawn on the seat colour has to
  /// be dark to stay readable.
  static const double darkMarkAbove = 0.45;

  /// Whether a mark on a tile of [luminance] must be dark (`true`) or light.
  static bool darkMarkOn(double luminance) => luminance > darkMarkAbove;

  /// Chevron polyline for a chevron centred on the origin pointing along
  /// `+x`: three points, tip in the middle.
  static List<Pt> chevronPoints() => const [
        Pt(-chevronHalfLength, -chevronHalfWidth),
        Pt(chevronHalfLength, 0),
        Pt(-chevronHalfLength, chevronHalfWidth),
      ];

  /// Longest distance of any chevron point from the cell centre (used by the
  /// tests to keep it inside the tile).
  static double get chevronReach => chevronPoints()
      .map((p) => math.sqrt(p.x * p.x + p.y * p.y))
      .reduce(math.max);
}
