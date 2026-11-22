/// Seat name plates: a pill with the player's name and an "n/4 home" chip,
/// one per seat, in the empty margin beyond the dock (and its roll tray) so it
/// faces outward like the toasts do (polish pass, step 4). Pure Dart, no
/// Flutter.
library;

import 'package:ludo/engine/ludo_engine.dart';

import 'table_layout.dart';

/// Where one seat's plate sits and which way it faces.
class SeatPlate {
  const SeatPlate({required this.seat, required this.box, required this.edge});

  final int seat;

  /// The plate in table space. Its long side runs along the table edge.
  final Box box;

  /// The table edge the seat faces (the text is turned toward it).
  final SeatEdge edge;

  /// Length along the table edge and depth away from it, pixels.
  double get along =>
      edge == SeatEdge.top || edge == SeatEdge.bottom ? box.width : box.height;
  double get depth =>
      edge == SeatEdge.top || edge == SeatEdge.bottom ? box.height : box.width;
}

class SeatPlates {
  const SeatPlates._();

  /// Plate length along the table edge (cells): the same footprint as the
  /// roll tray, so neighbours in one margin never meet.
  static const double alongCells = TableLayout.trayAlongCells;

  /// Plate depth (cells): at most [maxDepthCells]; a margin with less than
  /// [minDepthCells] left gets no plate.
  static const double maxDepthCells = 1.3;
  static const double minDepthCells = 0.95;

  /// Gap to the tray (or dock) in cells and to the screen edge in pixels.
  static const double gapCells = 0.15;
  static const double screenGapPx = 6;

  /// Tokens of [seat] that reached the finish.
  static int homeCount(GameState state, int seat) {
    var n = 0;
    for (final position in state.tokens[seat]) {
      if (position == finishPosition) {
        n++;
      }
    }
    return n;
  }

  /// The "n/4 home" chip text.
  static String homeLabel(int home) => '$home/$tokensPerSeat';

  /// One plate per seat, `null` where the margin is too small (docks inside
  /// the yards, short screens). A plate sits just beyond the dock's roll
  /// tray, on the player's side, never over a dock, a tray or the menu.
  static List<SeatPlate?> compute(TableLayout layout) {
    if (layout.placement == DockPlacement.inYard) {
      return List<SeatPlate?>.filled(layout.docks.length, null);
    }
    final cell = layout.cell;
    final gap = gapCells * cell;
    final along = alongCells * cell;
    return [
      for (final dock in layout.docks)
        _plateFor(layout, dock, cell, gap, along),
    ];
  }

  static SeatPlate? _plateFor(
    TableLayout layout,
    DockLayout dock,
    double cell,
    double gap,
    double along,
  ) {
    // The margin beyond everything that already sits there.
    final inner = dock.trayOuter ? dock.tray : dock.rect;
    final c = dock.rect.center;
    final double room;
    switch (dock.edge) {
      case SeatEdge.top:
        room = inner.top - gap - screenGapPx;
      case SeatEdge.bottom:
        room = layout.height - screenGapPx - (inner.bottom + gap);
      case SeatEdge.left:
        room = inner.left - gap - screenGapPx;
      case SeatEdge.right:
        room = layout.width - screenGapPx - (inner.right + gap);
    }
    if (room < minDepthCells * cell) {
      return null;
    }
    final depth = room < maxDepthCells * cell ? room : maxDepthCells * cell;
    final Box box;
    switch (dock.edge) {
      case SeatEdge.top:
        box = Box(c.x - along / 2, inner.top - gap - depth, along, depth);
      case SeatEdge.bottom:
        box = Box(c.x - along / 2, inner.bottom + gap, along, depth);
      case SeatEdge.left:
        box = Box(inner.left - gap - depth, c.y - along / 2, depth, along);
      case SeatEdge.right:
        box = Box(inner.right + gap, c.y - along / 2, depth, along);
    }
    return SeatPlate(seat: dock.seat, box: box, edge: dock.edge);
  }
}
