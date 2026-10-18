import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/dock_look.dart';
import 'package:ludo/ui/core/frame_stats.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';
import 'wood_frame.dart';

/// Turn light, drawn over the cached board and under the tokens: the active
/// yard breathes an inner glow (period 2 s); the other yards are washed out
/// a little. When the turn passes, the light fades out of one yard and into
/// the next over the dock handoff time, so it visibly travels. No text needed
/// to see whose turn it is.
class YardGlowPainter extends CustomPainter {
  YardGlowPainter({
    required this.game,
    required this.palette,
    required this.shaders,
  }) : super(repaint: game.clock);

  final GameController game;
  final LudoPalette palette;
  final TokenShaders shaders;

  /// Breathing period.
  static const double periodMs = 2000;

  final Paint _paint = Paint();

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
    final breath = 0.5 - 0.5 * math.cos(2 * math.pi * now / periodMs);
    for (var s = 0; s < 4; s++) {
      // 1 = fully lit, 0 = washed out; the handoff fades between them.
      final live = active == null
          ? 0.0
          : DockLook.live(
              active: s == active,
              wasActive: s == game.prevActiveSeat,
              sinceMs: now - game.activeSinceMs,
              spec: game.spec,
            );
      final yard = TokenShaders.yardRect(s);
      if (live > 0.01) {
        final strength = (70 + 120 * breath) / 190 * live;
        _paint
          ..color = const Color(0xFF000000)
          ..shader = shaders.yardGlow[s]
          ..colorFilter = ColorFilter.mode(
            Color.fromRGBO(0, 0, 0, strength.clamp(0.0, 1.0)),
            BlendMode.dstIn,
          );
        canvas.drawRect(yard, _paint);
        _paint
          ..shader = null
          ..colorFilter = null;
      }
      if (live < 0.99) {
        _paint.color = palette.board.withAlpha((38 * (1 - live)).round());
        canvas.drawRect(yard, _paint);
      }
    }
    canvas.restore();
    PaintProbe.stop(probe);
  }

  @override
  bool shouldRepaint(YardGlowPainter oldDelegate) =>
      oldDelegate.game != game ||
      oldDelegate.palette != palette ||
      oldDelegate.shaders != shaders;
}
