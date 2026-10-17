import 'package:flutter/widgets.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import 'dock_painter.dart';

/// The docks: painted mats and dice, plus one big tap target per seat (the
/// whole dock rolls, not just the die).
class DockLayer extends StatelessWidget {
  const DockLayer({
    super.key,
    required this.game,
    required this.layout,
    required this.palette,
  });

  final GameController game;
  final TableLayout layout;
  final LudoPalette palette;

  @override
  Widget build(BuildContext context) {
    // Docks inside the yards (tiny screens) would sit on the tokens, so they
    // must not eat taps while a token is being chosen.
    final yardsBusy = layout.placement == DockPlacement.inYard &&
        game.phase == GamePhase.awaitingMove;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: CustomPaint(
            painter: DockPainter(game: game, layout: layout, palette: palette),
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
      ],
    );
  }
}
