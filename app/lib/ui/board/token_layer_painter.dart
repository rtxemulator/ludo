import 'package:flutter/rendering.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/dice_timeline.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/token_timeline.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';

class _Item {
  _Item(this.seat, this.index, this.pos, this.pose, this.scale);

  final int seat;
  final int index;
  final Pt pos;
  final TokenPose? pose;
  final double scale;
}

/// Dynamic layer: tokens, shadows, legal-move glow and the finish ring.
///
/// It only *samples* `MoveAnimationPlan` / `PulseSample` (pure functions of
/// time from `lib/ui/core`); no animation numbers live here. Repaints on the
/// controller's frame clock.
class TokenLayerPainter extends CustomPainter {
  TokenLayerPainter({
    required this.game,
    required this.palette,
    required this.shaders,
  }) : super(repaint: game.clock);

  final GameController game;
  final LudoPalette palette;
  final TokenShaders shaders;

  static const double _bodyRadius = 0.34;

  final Paint _shadow = Paint();
  final Paint _body = Paint();
  final Paint _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.14
    ..color = const Color(0xD9FFFFFF);
  final Paint _shine = Paint()..color = const Color(0x59FFFFFF);
  final Paint _glow = Paint();
  final Paint _ring = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / BoardGeometry.gridSize);

    final now = game.clock.value;
    final state = game.state;
    final plan = game.plan;
    final planT = now - game.planStartMs;

    // Legal-move glow sits under the tokens.
    if (game.phase == GamePhase.awaitingMove) {
      final pulse = PulseSample.at(now, game.spec);
      for (final move in game.legal) {
        final p = game.resting[move.owner][move.tokenIndex];
        final center = Offset(p.x, p.y);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.scale(pulse.radius * 1.6);
        _glow.shader = shaders.glow[move.owner];
        canvas.drawCircle(Offset.zero, 1, _glow);
        canvas.restore();
        _ring
          ..strokeWidth = 0.07
          ..color = palette.seatLight(move.owner).withAlpha(
                (pulse.opacity * 255).round().clamp(0, 255),
              );
        canvas.drawCircle(center, pulse.radius, _ring);
      }
    }

    // Tokens, lower rows later so they overlap the ones above them.
    final items = <_Item>[];
    for (final seat in state.activeSeats) {
      for (var i = 0; i < tokensPerSeat; i++) {
        final pose = plan?.poseOf(seat, i, planT);
        var scale = game.restScales[seat][i];
        if (pose != null && plan != null) {
          scale = (seat == plan.owner && i == plan.tokenIndex)
              ? game.moverBaseScale
              : 1.0;
        }
        items.add(
            _Item(seat, i, pose?.pos ?? game.resting[seat][i], pose, scale));
      }
    }
    items.sort((a, b) {
      final aMoving = a.pose != null ? 1 : 0;
      final bMoving = b.pose != null ? 1 : 0;
      if (aMoving != bMoving) {
        return aMoving - bMoving;
      }
      return a.pos.y.compareTo(b.pos.y);
    });
    for (final item in items) {
      _drawToken(canvas, item);
    }

    // Finish ring.
    final ring = plan?.ring;
    if (ring != null) {
      final r = ring.sample(planT);
      if (r.opacity > 0) {
        _ring
          ..strokeWidth = 0.08
          ..color = palette.seatLight(plan!.owner).withAlpha(
                (r.opacity * 255).round().clamp(0, 255),
              );
        canvas.drawCircle(
            Offset(ring.center.x, ring.center.y), r.radius, _ring);
      }
    }

    canvas.restore();
  }

  void _drawToken(Canvas canvas, _Item item) {
    final pose = item.pose;
    final lift = pose?.lift ?? 0;
    final grow = pose?.scale ?? 1;
    final opacity = pose?.opacity ?? 1;
    final ground = Offset(item.pos.x, item.pos.y);
    final r = _bodyRadius * item.scale * grow;

    final faded = opacity < 1;
    if (faded) {
      canvas.saveLayer(
        Rect.fromCircle(center: ground, radius: 1.2),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }

    // Shadow stays on the ground (the full pawn/parallax shadow is step P3).
    final air = (1 - lift * 0.4).clamp(0.4, 1.0);
    _shadow.color = Color.fromRGBO(0, 0, 0, 0.28 * air);
    canvas.drawOval(
      Rect.fromCenter(
        center: ground,
        width: 0.84 * item.scale * grow * air,
        height: 0.84 * item.scale * grow * air,
      ),
      _shadow,
    );

    // Body: unit circle scaled to the radius. Height is scale (already in
    // `grow`), so it is not moved up the screen.
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(r);
    _body.shader = shaders.body[item.seat];
    canvas.drawCircle(Offset.zero, 1, _body);
    canvas.drawCircle(Offset.zero, 0.92, _rim);
    canvas.drawCircle(const Offset(-0.32, -0.38), 0.26, _shine);
    canvas.restore();

    if (faded) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(TokenLayerPainter oldDelegate) => true;
}
