import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/board_polish.dart';
import 'package:ludo/ui/core/dock_look.dart';
import 'package:ludo/ui/core/frame_stats.dart';
import 'package:ludo/ui/core/turn_focus.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';
import 'wood_frame.dart';

/// Turn focus, drawn over the cached board and under the tokens: the yard of
/// the seat on turn gets a crisp pulsing ring in the coloured border of its
/// quadrant and a light glow on that border (`TurnFocus`, pure numbers in
/// `lib/ui/core`). When the turn passes the focus fades out of one yard and
/// into the next over the dock handoff time, so it visibly travels.
///
/// Yards that are not on turn are left alone (full colour, no wash), so the
/// board does not flicker in brightness each turn. Yards of empty seats are
/// veiled. No shader and no gradient: two stroked rounded rectangles.
class YardGlowPainter extends CustomPainter {
  YardGlowPainter({required this.game, required this.palette})
      : super(repaint: game.clock);

  final GameController game;
  final LudoPalette palette;

  final Paint _paint = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final probe = PaintProbe.start();
    canvas.save();
    canvas.scale(size.width / BoardGeometry.gridSize);
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 15, 15),
        const Radius.circular(boardCornerRadius),
      ),
    );

    final now = game.clock.value;
    final active = game.activeSeat;
    for (var s = 0; s < 4; s++) {
      final yard = TokenShaders.yardRect(s);
      if (!game.state.isActive(s)) {
        // An empty seat (2 and 3 player tables): the yard is mostly washed
        // out.
        _paint.color = palette.board.withAlpha(170);
        canvas.drawRect(yard, _paint);
        continue;
      }
      if (active == null) {
        continue;
      }
      final live = DockLook.live(
        active: s == active,
        wasActive: s == game.prevActiveSeat,
        sinceMs: now - game.activeSinceMs,
        spec: game.spec,
      );
      final focus = TurnFocus.sample(now, live, game.spec);
      if (!focus.visible) {
        continue;
      }
      // The middle of the quadrant's coloured border, concentric with the
      // panel (inset 1, radius 0.6).
      final middle = RRect.fromRectAndRadius(
        yard.deflate(TurnFocus.ringCentre),
        Radius.circular(0.6 + BoardPolish.yardInset - TurnFocus.ringCentre),
      );
      if (focus.glowAlpha > 0.01) {
        _stroke
          ..strokeWidth = TurnFocus.glowWidth
          ..color = palette
              .seatLight(s)
              .withAlpha((focus.glowAlpha * 255).round().clamp(0, 255));
        canvas.drawRRect(middle, _stroke);
      }
      if (focus.ringAlpha > 0.01) {
        _stroke
          ..strokeWidth = focus.ringWidth
          ..color = palette
              .onSeat(s)
              .withAlpha((focus.ringAlpha * 255).round().clamp(0, 255));
        canvas.drawRRect(middle, _stroke);
      }
    }
    canvas.restore();
    PaintProbe.stop(probe);
  }

  @override
  bool shouldRepaint(YardGlowPainter oldDelegate) =>
      oldDelegate.game != game || oldDelegate.palette != palette;
}
