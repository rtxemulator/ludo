import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/pt.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import 'wood_frame.dart';

/// Turn light, drawn over the cached board and under the tokens: the active
/// yard breathes an inner glow (period 2 s); the other yards are washed out
/// a little. No text needed to see whose turn it is.
class YardGlowPainter extends CustomPainter {
  YardGlowPainter({required this.game, required this.palette})
      : super(repaint: game.clock);

  final GameController game;
  final LudoPalette palette;

  /// Breathing period.
  static const double periodMs = 2000;

  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / BoardGeometry.gridSize);
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 15, 15),
        const Radius.circular(boardCornerRadius),
      ),
    );

    final active = game.activeSeat;
    final breath =
        0.5 - 0.5 * math.cos(2 * math.pi * game.clock.value / periodMs);
    for (var s = 0; s < 4; s++) {
      final a = BoardGeometry.rotate(const Pt(0, 0), s);
      final b = BoardGeometry.rotate(const Pt(6, 6), s);
      final yard = Rect.fromPoints(Offset(a.x, a.y), Offset(b.x, b.y));
      if (s == active) {
        final glow = palette.seatLight(s);
        _paint
          ..color = const Color(0xFF000000)
          ..shader = RadialGradient(
            radius: 0.75,
            colors: [
              glow.withAlpha(0),
              glow.withAlpha((70 + 120 * breath).round())
            ],
            stops: const [0.5, 1.0],
          ).createShader(yard);
        canvas.drawRect(yard, _paint);
        _paint.shader = null;
      } else {
        _paint.color = palette.board.withAlpha(38);
        canvas.drawRect(yard, _paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(YardGlowPainter oldDelegate) =>
      oldDelegate.game != game || oldDelegate.palette != palette;
}
