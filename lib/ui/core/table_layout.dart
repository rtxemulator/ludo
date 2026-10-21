/// Table layout: where the board, the per-seat docks and the menu button
/// sit on the screen, and which way text for each seat must face.
/// Pure Dart, no Flutter. Spec: docs/ludo-ui-ux.md sections 2 and 3.
///
/// All lengths are logical pixels unless a name says `Cells`.
library;

import 'board_geometry.dart';
import 'pt.dart';

/// Axis-aligned rectangle (pixels).
class Box {
  const Box(this.left, this.top, this.width, this.height);

  /// Box of [width] x [height] centred on [center].
  factory Box.centered(Pt center, double width, double height) =>
      Box(center.x - width / 2, center.y - height / 2, width, height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  Pt get center => Pt(left + width / 2, top + height / 2);

  bool contains(Pt p) =>
      p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;

  /// Whether [other] lies inside this box (within [eps]).
  bool containsBox(Box other, {double eps = 1e-6}) =>
      other.left >= left - eps &&
      other.top >= top - eps &&
      other.right <= right + eps &&
      other.bottom <= bottom + eps;

  /// Whether the interiors overlap by more than [eps].
  bool overlaps(Box other, {double eps = 1e-6}) =>
      left < other.right - eps &&
      other.left < right - eps &&
      top < other.bottom - eps &&
      other.top < bottom - eps;

  @override
  String toString() => 'Box($left, $top, ${width}x$height)';
}

/// The table edge a seat sits at (and whose text faces it).
enum SeatEdge { bottom, left, top, right }

/// Where the docks live.
enum DockPlacement {
  /// In the margins above and below the board (phones in portrait).
  topBottom,

  /// In the margins left and right of the board (landscape, tablets).
  leftRight,

  /// Margins too small: inside the yards.
  inYard,
}

/// `Table` = text faces each seat; `Fixed` = everything upright.
enum UiOrientation { table, fixed }

/// One seat's dock (the zone where its die lands).
class DockLayout {
  const DockLayout({
    required this.seat,
    required this.rect,
    required this.dieCenter,
    required this.dieSize,
    required this.edge,
    required this.tray,
    required this.chipSize,
    required this.trayOuter,
  });

  final int seat;
  final Box rect;
  final Pt dieCenter;

  /// Die edge length in pixels.
  final double dieSize;

  /// Table edge this seat faces.
  final SeatEdge edge;

  /// Where the banked-roll chips sit (UI/UX doc section 10), pixels. It is
  /// a strip beyond the dock on the player's side ([trayOuter]) when the
  /// margin has room, otherwise the strip of the dock between the die and the
  /// player's edge.
  final Box tray;

  /// Chip edge length in pixels.
  final double chipSize;

  /// Whether [tray] lies outside [rect] (it never overlaps the dock then).
  final bool trayOuter;

  /// The tray's length along the table edge, in chips.
  double get trayCapacity => _alongOf(tray, edge) / chipSize;

  /// Tray centre in table space.
  Pt get trayCenter => tray.center;

  static double _alongOf(Box b, SeatEdge edge) =>
      edge == SeatEdge.top || edge == SeatEdge.bottom ? b.width : b.height;
}

/// Pure layout of the table for a screen of [width] x [height] pixels.
class TableLayout {
  TableLayout._({
    required this.width,
    required this.height,
    required this.cell,
    required this.frame,
    required this.board,
    required this.docks,
    required this.menu,
    required this.placement,
  });

  /// Thickness of the wooden frame around the 15 x 15 grid, in cells.
  static const double frameCells = 0.45;

  /// Dock zone: length along its table edge and depth away from it.
  static const double dockAlongCells = 4.5;
  static const double dockDepthCells = 3.5;

  /// Die size in a dock (cells).
  static const double dieCells = 1.9;

  /// A margin smaller than this (in cells) cannot hold a dock.
  static const double minMarginCells = 3.0;

  /// Gap between a dock and the board frame (cells).
  static const double gapCells = 0.15;

  /// Roll tray (banked rolls): chip edge, strip depth and length along the
  /// table edge, gap to the dock, and the least outside room worth using.
  static const double chipCells = 1.1;
  static const double trayDepthCells = 1.5;
  static const double trayAlongCells = 6.0;
  static const double trayGapCells = 0.1;
  static const double trayMinOuterCells = 1.0;

  /// Menu button edge, pixels (a comfortable touch target).
  static const double menuPx = 44;

  /// Framed board side in cells.
  static const double framedCells = BoardGeometry.gridSize + 2 * frameCells;

  /// Computes the layout for a [width] x [height] area with [padding] on
  /// every side.
  factory TableLayout.compute({
    required double width,
    required double height,
    double padding = 8,
  }) {
    assert(width > 0 && height > 0);
    final short = (width < height ? width : height) - 2 * padding;
    var cell = short / framedCells;

    // A slightly smaller board (up to 10%) can buy the margins a dock needs
    // (tablets and near-square screens); beyond that the docks move into
    // the yards instead.
    final axisLength = height >= width ? height : width;
    final fitCell = axisLength / (framedCells + 2 * minMarginCells);
    if (fitCell < cell && fitCell >= 0.9 * cell) {
      cell = fitCell;
    }

    var side = framedCells * cell;
    final marginV = (height - side) / 2;
    final marginH = (width - side) / 2;
    final verticalPair = marginV >= marginH;
    final bestMargin = (verticalPair ? marginV : marginH) / cell;

    var placement =
        verticalPair ? DockPlacement.topBottom : DockPlacement.leftRight;
    var boardTop = (height - side) / 2;
    final fits = bestMargin >= minMarginCells - 1e-9;
    if (!fits) {
      placement = DockPlacement.inYard;
      // Reserve a strip at the top of the screen for the menu button.
      final strip = menuPx + padding;
      final byHeight = (height - 2 * padding - strip) / framedCells;
      cell = byHeight < cell ? byHeight : cell;
      side = framedCells * cell;
      boardTop = strip + (height - strip - side) / 2;
    }
    final left = (width - side) / 2;
    final frame = Box(left, boardTop, side, side);
    final inner = frame.width - 2 * frameCells * cell;
    final board = Box(
      left + frameCells * cell,
      boardTop + frameCells * cell,
      inner,
      inner,
    );

    // Which edge each seat faces.
    const portraitEdges = [
      SeatEdge.top,
      SeatEdge.top,
      SeatEdge.bottom,
      SeatEdge.bottom,
    ];
    const landscapeEdges = [
      SeatEdge.left,
      SeatEdge.right,
      SeatEdge.right,
      SeatEdge.left,
    ];
    final useVerticalEdges = placement == DockPlacement.topBottom ||
        (placement == DockPlacement.inYard && height >= width);
    final edges = useVerticalEdges ? portraitEdges : landscapeEdges;

    // Yard centres in board cells (seat 0 TL, 1 TR, 2 BR, 3 BL).
    const yardCentres = [Pt(3, 3), Pt(12, 3), Pt(12, 12), Pt(3, 12)];
    final gap = gapCells * cell;
    final docks = <DockLayout>[];
    for (var seat = 0; seat < 4; seat++) {
      final yard = yardCentres[seat];
      final cx = board.left + yard.x * cell;
      final cy = board.top + yard.y * cell;
      final Box rect;
      double dieSize;
      switch (placement) {
        case DockPlacement.topBottom:
          final depth = _depth(cell, bestMargin);
          final along = dockAlongCells * cell;
          final isUpper = edges[seat] == SeatEdge.top;
          final y = isUpper ? frame.top - gap - depth : frame.bottom + gap;
          rect = Box(cx - along / 2, y, along, depth);
          dieSize = _dieFor(cell, depth);
        case DockPlacement.leftRight:
          final depth = _depth(cell, bestMargin);
          final along = dockAlongCells * cell;
          final isLeft = edges[seat] == SeatEdge.left;
          final x = isLeft ? frame.left - gap - depth : frame.right + gap;
          rect = Box(x, cy - along / 2, depth, along);
          dieSize = _dieFor(cell, depth);
        case DockPlacement.inYard:
          final s = 3.2 * cell;
          rect = Box.centered(Pt(cx, cy), s, s);
          dieSize = 1.4 * cell;
      }
      final tray = _trayFor(
        placement: placement,
        edge: edges[seat],
        rect: rect,
        dieSize: dieSize,
        cell: cell,
        width: width,
        height: height,
      );
      docks.add(
        DockLayout(
          seat: seat,
          rect: rect,
          dieCenter: rect.center,
          dieSize: dieSize,
          edge: edges[seat],
          tray: tray.box,
          chipSize: tray.chip,
          trayOuter: tray.outer,
        ),
      );
    }

    const menuSize = menuPx;
    final Pt menuCenter;
    switch (placement) {
      case DockPlacement.topBottom:
        menuCenter = Pt(width / 2, frame.top - gap - menuSize / 2);
      case DockPlacement.leftRight:
        menuCenter = Pt(frame.left / 2, height / 2);
      case DockPlacement.inYard:
        menuCenter = Pt(width / 2, padding + menuSize / 2);
    }

    return TableLayout._(
      width: width,
      height: height,
      cell: cell,
      frame: frame,
      board: board,
      docks: docks,
      menu: Box.centered(menuCenter, menuSize, menuSize),
      placement: placement,
    );
  }

  /// The roll tray of one dock: the strip beyond the dock on the player's
  /// side if the margin has [trayMinOuterCells] to spare, otherwise the strip
  /// of the dock between the die and the player's edge.
  static ({Box box, double chip, bool outer}) _trayFor({
    required DockPlacement placement,
    required SeatEdge edge,
    required Box rect,
    required double dieSize,
    required double cell,
    required double width,
    required double height,
  }) {
    final horizontalEdge = edge == SeatEdge.top || edge == SeatEdge.bottom;
    final gap = trayGapCells * cell;
    final room = switch (edge) {
      SeatEdge.bottom => height - rect.bottom,
      SeatEdge.top => rect.top,
      SeatEdge.left => rect.left,
      SeatEdge.right => width - rect.right,
    };
    final outerDepth = room - gap;
    if (placement != DockPlacement.inYard &&
        outerDepth >= trayMinOuterCells * cell) {
      final depth = outerDepth < trayDepthCells * cell
          ? outerDepth
          : trayDepthCells * cell;
      final along = trayAlongCells * cell;
      final c = rect.center;
      final box = switch (edge) {
        SeatEdge.bottom =>
          Box(c.x - along / 2, rect.bottom + gap, along, depth),
        SeatEdge.top =>
          Box(c.x - along / 2, rect.top - gap - depth, along, depth),
        SeatEdge.left =>
          Box(rect.left - gap - depth, c.y - along / 2, depth, along),
        SeatEdge.right => Box(rect.right + gap, c.y - along / 2, depth, along),
      };
      return (box: box, chip: _chipFor(cell, depth), outer: true);
    }
    // Inside the dock: the strip between the die and the player's edge.
    final dockDepth = horizontalEdge ? rect.height : rect.width;
    final depth = (dockDepth - dieSize) / 2;
    final box = switch (edge) {
      SeatEdge.bottom => Box(rect.left, rect.bottom - depth, rect.width, depth),
      SeatEdge.top => Box(rect.left, rect.top, rect.width, depth),
      SeatEdge.left => Box(rect.left, rect.top, depth, rect.height),
      SeatEdge.right => Box(rect.right - depth, rect.top, depth, rect.height),
    };
    return (box: box, chip: _chipFor(cell, depth), outer: false);
  }

  static double _chipFor(double cell, double depth) {
    final byDepth = depth * 0.8;
    final preferred = chipCells * cell;
    return byDepth < preferred ? byDepth : preferred;
  }

  static double _depth(double cell, double marginCells) {
    final usable = marginCells - gapCells;
    final cells = usable < dockDepthCells ? usable : dockDepthCells;
    return cells * cell;
  }

  static double _dieFor(double cell, double depth) {
    final byDepth = depth * 0.8;
    final preferred = dieCells * cell;
    return byDepth < preferred ? byDepth : preferred;
  }

  final double width;
  final double height;

  /// Board cell size in pixels (the 15 x 15 grid).
  final double cell;

  /// Wooden frame (outer square).
  final Box frame;

  /// The 15 x 15 grid (inside the frame).
  final Box board;

  /// One dock per seat, indexed by seat.
  final List<DockLayout> docks;

  /// Round menu button.
  final Box menu;
  final DockPlacement placement;

  /// The table edge [seat] faces.
  SeatEdge edgeOf(int seat) => docks[seat].edge;
}

/// Quarter turns clockwise to apply to [edge]-facing text.
int turnsForEdge(SeatEdge edge) {
  switch (edge) {
    case SeatEdge.bottom:
      return 0;
    case SeatEdge.left:
      return 1;
    case SeatEdge.top:
      return 2;
    case SeatEdge.right:
      return 3;
  }
}

/// Quarter turns clockwise for text addressed to [seat] (toasts, rank
/// badges, bank hints): outward toward the seat's edge in `Table` mode,
/// upright in `Fixed` mode.
int seatTextTurns(TableLayout layout, int seat, UiOrientation mode) =>
    mode == UiOrientation.fixed ? 0 : turnsForEdge(layout.edgeOf(seat));

/// Quarter turns for shared UI (menu sheet, game-over card): follows the
/// active seat only in `Table` mode with [autoRotate] on.
int sharedUiTurns(
  TableLayout layout,
  int activeSeat,
  UiOrientation mode, {
  bool autoRotate = true,
}) =>
    mode == UiOrientation.table && autoRotate
        ? seatTextTurns(layout, activeSeat, mode)
        : 0;

/// Rotates the vector [v] clockwise on screen (y points down) by
/// [quarterTurns] x 90 degrees: `(x, y) -> (-y, x)` per turn.
///
/// A dock's local frame has `+y` toward the player's own edge; rotating it
/// by [turnsForEdge] turns that into the screen direction of the edge.
Pt rotateQuarterTurns(Pt v, int quarterTurns) {
  switch (((quarterTurns % 4) + 4) % 4) {
    case 1:
      return Pt(-v.y, v.x);
    case 2:
      return Pt(-v.x, -v.y);
    case 3:
      return Pt(v.y, -v.x);
    default:
      return v;
  }
}
