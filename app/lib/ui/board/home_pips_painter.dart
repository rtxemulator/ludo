import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/board_polish.dart';
import 'package:ludo/ui/core/frame_stats.dart';
import 'package:ludo/ui/core/pt.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';

/// Dynamic layer: each seat's tokens-home count, drawn as a row of four pips
/// in that seat's centre triangle (a filled pip per token that reached the
/// finish square). Pips have no "up", so the count reads the same from every
/// side of the table, and the screen still has no text.
///
/// It repaints only when the controller notifies (a state change), never per
/// frame, and sits in its own `RepaintBoundary` between the cached board and
/// the tokens.
class HomePipsPainter extends CustomPainter {
  HomePipsPainter({required this.game, required this.palette})
      : super(repaint: game);

  final GameController game;
  final LudoPalette palette;

  final Paint _fill = Paint();
  final Paint _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final probe = PaintProbe.start();
    canvas.save();
    canvas.scale(size.width / BoardGeometry.gridSize);
    final state = game.state;
    for (final seat in state.activeSeats) {
      final home = BoardPolish.homeCount(state.tokens[seat]);
      final mark = palette.onSeat(seat);
      for (var slot = 0; slot < 4; slot++) {
        final Pt c = BoardPolish.pipCentre(seat, slot);
        final centre = Offset(c.x, c.y);
        final filled = slot < home;
        _fill.color = filled ? mark : mark.withAlpha(46);
        canvas.drawCircle(centre, BoardPolish.pipRadius, _fill);
        _edge.color = mark.withAlpha(filled ? 255 : 120);
        canvas.drawCircle(centre, BoardPolish.pipRadius, _edge);
      }
    }
    canvas.restore();
    PaintProbe.stop(probe);
  }

  @override
  bool shouldRepaint(HomePipsPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.game != game;
}
