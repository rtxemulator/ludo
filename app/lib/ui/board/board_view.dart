import 'package:flutter/widgets.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/token_look.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';
import 'home_pips_painter.dart';
import 'token_layer_painter.dart';
import 'yard_glow_painter.dart';

/// The 15 x 15 playing area: turn light + animated tokens + tap handling.
///
/// The parent sizes it to the inner board (inside the frame); the cached
/// static board and frame are drawn beneath it by the table view.
class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.game,
    required this.palette,
    required this.shaders,
  });

  final GameController game;
  final LudoPalette palette;
  final TokenShaders shaders;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = constraints.biggest.width / BoardGeometry.gridSize;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final p = details.localPosition;
            game.tapAt(
              Pt(p.dx / cell, p.dy / cell),
              reach: TokenLook.tapReach(cell),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Dynamic layers, each in its own RepaintBoundary so one
              // layer repainting never re-rasterises another.
              RepaintBoundary(
                child: CustomPaint(
                  painter: YardGlowPainter(
                    game: game,
                    palette: palette,
                    shaders: shaders,
                  ),
                ),
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: HomePipsPainter(game: game, palette: palette),
                ),
              ),
              for (final part in TokenLayerPart.values)
                RepaintBoundary(
                  child: CustomPaint(
                    painter: TokenLayerPainter(
                      game: game,
                      palette: palette,
                      shaders: shaders,
                      part: part,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
