import 'package:flutter/widgets.dart';
import 'package:ludo/ui/core/bank_tray.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import 'dock_painter.dart';
import 'tray_painter.dart';

/// The docks: painted mats and dice, plus one big tap target per seat (the
/// whole dock rolls, not just the die). With banked rolls it also holds the
/// roll trays: painted chips and, while dice are to be spent, a tap target
/// per tray that selects a chip.
class DockLayer extends StatelessWidget {
  const DockLayer({
    super.key,
    required this.game,
    required this.layout,
    required this.palette,
    this.orientation = UiOrientation.table,
  });

  final GameController game;
  final TableLayout layout;
  final LudoPalette palette;
  final UiOrientation orientation;

  /// A tap in tray [dock] at [local] (relative to the tray's top left).
  void _trayTap(DockLayout dock, Offset local) {
    final centred = Pt(
      local.dx - dock.tray.width / 2,
      local.dy - dock.tray.height / 2,
    );
    // Back into the dock's frame (+x along the player's edge).
    final v = rotateQuarterTurns(centred, -turnsForEdge(dock.edge));
    final count = game.tray.presentOf(dock.seat).length;
    final chip = hitChip(
      v.x / dock.chipSize,
      count,
      game.tray.capacity[dock.seat],
      slop: 0.9,
    );
    if (chip >= 0) {
      game.chipTap(dock.seat, chip);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Docks inside the yards (tiny screens) would sit on the tokens, so they
    // must not eat taps while a token is being chosen.
    final yardsBusy = layout.placement == DockPlacement.inYard &&
        game.phase == GamePhase.awaitingMove;
    game.syncTrayCapacity([for (final d in layout.docks) d.trayCapacity]);
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: CustomPaint(
            painter: DockPainter(game: game, layout: layout, palette: palette),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: TrayPainter(
              game: game,
              layout: layout,
              palette: palette,
              orientation: orientation,
            ),
          ),
        ),
        for (final dock in layout.docks)
          Positioned(
            left: dock.rect.left,
            top: dock.rect.top,
            width: dock.rect.width,
            height: dock.rect.height,
            child: IgnorePointer(
              ignoring: yardsBusy,
              child: GestureDetector(
                key: ValueKey<String>('dock-${dock.seat}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => game.dockTap(dock.seat),
              ),
            ),
          ),
        for (final dock in layout.docks)
          if (game.trayTappable(dock.seat))
            Positioned(
              left: dock.tray.left,
              top: dock.tray.top,
              width: dock.tray.width,
              height: dock.tray.height,
              child: GestureDetector(
                key: ValueKey<String>('tray-${dock.seat}'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _trayTap(dock, details.localPosition),
              ),
            ),
      ],
    );
  }
}
