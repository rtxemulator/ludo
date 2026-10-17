import 'package:flutter/widgets.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../board/board_painter.dart';
import '../board/board_view.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';
import 'felt_painter.dart';

/// Converts a pure-Dart [Box] to a Flutter [Rect].
Rect boxRect(Box b) => Rect.fromLTWH(b.left, b.top, b.width, b.height);

/// The whole table: felt, wooden frame with the board, tokens. Everything
/// is placed from [TableLayout] (pure Dart), so the painters never decide
/// where things go.
class TableView extends StatelessWidget {
  const TableView({
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
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
