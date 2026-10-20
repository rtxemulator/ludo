import 'package:flutter/material.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../board/board_painter.dart';
import '../board/board_view.dart';
import '../../settings/game_settings.dart';
import '../dev/frame_timing_overlay.dart';
import '../dice/dock_layer.dart';
import '../menu/game_over_card.dart';
import '../menu/table_menu.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';
import 'felt_painter.dart';
import 'overlay_painter.dart';

/// Converts a pure-Dart [Box] to a Flutter [Rect].
Rect boxRect(Box b) => Rect.fromLTWH(b.left, b.top, b.width, b.height);

/// The whole table: felt, wooden frame with the board, tokens and the four
/// docks. Everything is placed from [TableLayout] (pure Dart), so the
/// painters never decide where things go. Nothing else is on screen: whose
/// turn it is shows on the board (yard glow) and in the docks (live die).
class TableView extends StatelessWidget {
  const TableView({
    super.key,
    required this.game,
    required this.settings,
    required this.palette,
    required this.shaders,
  });

  final GameController game;
  final GameSettings settings;
  final LudoPalette palette;
  final TokenShaders shaders;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - inset.left - inset.right;
        final height = constraints.maxHeight - inset.top - inset.bottom;
        final layout = TableLayout.compute(width: width, height: height);
        final frame = boxRect(layout.frame);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Felt and frame shadow (baked once).
            RepaintBoundary(
              child: CustomPaint(
                painter: FeltPainter(
                  palette: palette,
                  frame: frame.shift(Offset(inset.left, inset.top)),
                ),
              ),
            ),
            Positioned(
              left: inset.left,
              top: inset.top,
              width: width,
              height: height,
              child: Stack(
                children: [
                  // Wooden frame + board (baked once).
                  Positioned.fromRect(
                    rect: frame,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        isComplex: true,
                        willChange: false,
                        painter: BoardPainter(palette),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: boxRect(layout.board),
                    child: BoardView(
                      game: game,
                      palette: palette,
                      shaders: shaders,
                    ),
                  ),
                  Positioned.fill(
                    child: DockLayer(
                      game: game,
                      layout: layout,
                      palette: palette,
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: OverlayPainter(
                          game: game,
                          layout: layout,
                          palette: palette,
                          orientation: settings.orientation,
                        ),
                      ),
                    ),
                  ),
                  if (game.phase == GamePhase.gameOver)
                    Positioned.fromRect(
                      rect: Rect.fromCenter(
                        center: Offset(
                          layout.board.center.x,
                          layout.board.center.y,
                        ),
                        width: GameOverCard.sideFor(layout),
                        height: GameOverCard.sideFor(layout),
                      ),
                      child: GameOverCard(
                        game: game,
                        settings: settings,
                        layout: layout,
                        onMenu: () => showTableMenu(
                          context,
                          game: game,
                          settings: settings,
                          layout: layout,
                        ),
                      ),
                    ),
                  _RoundButton(
                    rect: boxRect(layout.menu),
                    icon: Icons.menu,
                    tooltip: 'Menu',
                    color: palette.text,
                    onPressed: () => showTableMenu(
                      context,
                      game: game,
                      settings: settings,
                      layout: layout,
                    ),
                  ),
                  if (settings.frameOverlay)
                    const Positioned(
                      left: 4,
                      top: 4,
                      child: FrameTimingOverlay(),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Small round icon button on the felt.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.rect,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final Rect rect;
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: Material(
        type: MaterialType.circle,
        color: const Color(0x33000000),
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: color, size: 22),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
