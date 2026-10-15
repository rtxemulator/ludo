import 'package:flutter/widgets.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/pt.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';
import 'board_painter.dart';
import 'token_layer_painter.dart';

/// Square board: cached static layer + animated token layer + tap handling.
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
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cell = constraints.biggest.width / BoardGeometry.gridSize;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final p = details.localPosition;
              game.tapAt(Pt(p.dx / cell, p.dy / cell));
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: false,
                    painter: BoardPainter(palette),
                  ),
                ),
                CustomPaint(
                  painter: TokenLayerPainter(
                    game: game,
                    palette: palette,
                    shaders: shaders,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
