import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/frame_stats.dart';
import 'package:ludo/ui/core/fx.dart';
import 'package:ludo/ui/core/fx_scene.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/pulse.dart';
import 'package:ludo/ui/core/token_timeline.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';

/// Draw order: resting tokens first, then captured ones flying home, then
/// the mover on top.
enum _Layer { resting, victim, mover }

class _Item {
  _Item(
    this.seat,
    this.index,
    this.pos,
    this.pose,
    this.scale,
    this.layer,
    this.dim,
  );

  final int seat;
  final int index;
  final Pt pos;
  final TokenPose? pose;
  final double scale;
  final _Layer layer;

  /// Opacity lost to the "no legal move" dim (`0..1`).
  final double dim;
}

/// Dynamic layer: pawns, shadows, legal-move glow and the finish ring.
///
/// It only *samples* `MoveAnimationPlan` / `PulseSample` (pure functions of
/// time from `lib/ui/core`); no animation numbers live here. Repaints on the
/// controller's frame clock.
///
/// A pawn is a top-down disc with no "up" (UI/UX doc section 6): symmetric
/// shading, a centred shadow that only drifts radially away from the board
/// centre when the pawn is in the air, and height shown purely as scale.
class TokenLayerPainter extends CustomPainter {
  TokenLayerPainter({
    required this.game,
    required this.palette,
    required this.shaders,
  }) : super(repaint: game.clock);

  final GameController game;
  final LudoPalette palette;
  final TokenShaders shaders;

  /// Pawn base-ring radius at scale 1 (grid cells).
  static const double baseRadius = 0.38;

  /// Shadow growth and fade with height `h` (cells), and its radial drift.
  static const double shadowGrow = 0.35;
  static const double shadowFade = 2;
  static const double shadowDrift = 0.12;

  static const double _centre = BoardGeometry.gridSize / 2;

  final Paint _shadow = Paint();
  final Paint _fill = Paint();
  final Paint _specular = Paint()..color = const Color(0xC8FFFFFF);
  final Paint _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.05
    ..color = const Color(0x1FFFFFFF);
  final Paint _glow = Paint();
  final Paint _ring = Paint()..style = PaintingStyle.stroke;
  final Paint _spark = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final probe = PaintProbe.start();
    canvas.save();
    canvas.scale(size.width / BoardGeometry.gridSize);

    final now = game.clock.value;
    final state = game.state;
    final plan = game.plan;
    final planT = now - game.planStartMs;

    // Legal-move glow sits under everything.
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

    _drawGlows(canvas, now);

    final dimAmount = game.noMoveSeat == null
        ? 0.0
        : noMoveDim(now, game.noMoveMs, game.spec) * game.spec.noMoveDimAmount;

    // Stable seat/index order; no row sorting (a "lower row is nearer" rule
    // is wrong for the players sitting at the top).
    final items = <_Item>[];
    for (final seat in state.activeSeats) {
      for (var i = 0; i < tokensPerSeat; i++) {
        final pose = plan?.poseOf(seat, i, planT);
        var scale = game.restScales[seat][i];
        var layer = _Layer.resting;
        if (pose != null && plan != null) {
          final isMover = seat == plan.owner && i == plan.tokenIndex;
          scale = isMover ? game.moverBaseScale : 1.0;
          layer = isMover ? _Layer.mover : _Layer.victim;
        }
        var pos = pose?.pos ?? game.resting[seat][i];
        if (pose == null && !game.fx.nudges.isEmpty) {
          // A tapped token that cannot move shivers sideways.
          pos = Pt(
            pos.x + game.fx.nudgeOf(seat, i, now, game.spec),
            pos.y,
          );
        }
        items.add(_Item(
          seat,
          i,
          pos,
          pose,
          scale,
          layer,
          seat == game.noMoveSeat && pose == null ? dimAmount : 0,
        ));
      }
    }
    for (final layer in _Layer.values) {
      for (final item in items) {
        if (item.layer == layer) {
          _drawShadow(canvas, item);
        }
      }
    }
    for (final layer in _Layer.values) {
      for (final item in items) {
        if (item.layer == layer) {
          _drawPawn(canvas, item);
        }
      }
    }

    _drawFx(canvas, now);

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
    PaintProbe.stop(probe);
  }

  /// Pocket glow of a token that just reached home (under the pawns).
  void _drawGlows(Canvas canvas, double now) {
    for (final g in game.fx.glows) {
      final strength = g.sample(now);
      if (strength <= 0.01) {
        continue;
      }
      _glow
        ..shader = shaders.glow[g.seat]
        ..colorFilter = ColorFilter.mode(
          Color.fromRGBO(0, 0, 0, strength.clamp(0.0, 1.0)),
          BlendMode.dstIn,
        );
      canvas.save();
      canvas.translate(g.center.x, g.center.y);
      canvas.scale(1.35);
      canvas.drawCircle(Offset.zero, 1, _glow);
      canvas.restore();
      _glow.colorFilter = null;
    }
  }

  /// Rings (dust, shockwave, yard exit, ripple, nudge) and home sparks, over
  /// the pawns.
  void _drawFx(Canvas canvas, double now) {
    for (final r in game.fx.rings) {
      final s = r.ring.sample(now);
      if (s.opacity <= 0.004) {
        continue;
      }
      final Color color;
      final double width;
      switch (r.kind) {
        case FxKind.dust:
          color = palette.text;
          width = 0.06;
        case FxKind.shockwave:
          color = palette.seatLight(r.seat);
          width = 0.12;
        case FxKind.yardExit:
        case FxKind.ripple:
          color = palette.seatLight(r.seat);
          width = 0.07;
        case FxKind.nudge:
          color = _nudgeRed;
          width = 0.06;
      }
      _ring
        ..strokeWidth = width
        ..color = color.withAlpha((s.opacity * 255).round().clamp(0, 255));
      canvas.drawCircle(
          Offset(r.ring.center.x, r.ring.center.y), s.radius, _ring);
    }
    for (final burst in game.fx.sparks) {
      final sparks = burst.burst.sample(now);
      if (sparks.isEmpty) {
        continue;
      }
      final base = Color.lerp(
        palette.seatLight(burst.seat),
        const Color(0xFFFFFFFF),
        0.5,
      )!;
      for (final sp in sparks) {
        _spark.color = base.withAlpha((sp.opacity * 255).round().clamp(0, 255));
        canvas.drawCircle(Offset(sp.pos.x, sp.pos.y), sp.size, _spark);
      }
    }
  }

  static const Color _nudgeRed = Color(0xFFE53935);

  /// Centred contact core + penumbra. In the air the shadow widens, fades and
  /// drifts away from the board centre (radially symmetric parallax).
  void _drawShadow(Canvas canvas, _Item item) {
    final pose = item.pose;
    final lift = pose?.lift ?? 0;
    final poseScale = pose?.scale ?? 1;
    // The pose scale folds in height; the shadow keeps only the press / finish
    // shrink and handles height itself.
    final onGround = poseScale / (1 + game.spec.liftScaleGain * lift);
    final r = baseRadius * item.scale * onGround * (1 + shadowGrow * lift);
    final alpha =
        (pose?.opacity ?? 1) * (1 - item.dim) / (1 + shadowFade * lift);
    if (alpha <= 0.01 || r <= 0) {
      return;
    }

    var cx = item.pos.x;
    var cy = item.pos.y;
    if (lift > 0) {
      final vx = cx - _centre;
      final vy = cy - _centre;
      final len = math.sqrt(vx * vx + vy * vy);
      if (len > 1e-6) {
        cx += vx / len * shadowDrift * lift;
        cy += vy / len * shadowDrift * lift;
      }
    }

    _shadow.colorFilter = alpha < 0.999
        ? ColorFilter.mode(
            Color.fromRGBO(0, 0, 0, alpha),
            BlendMode.dstIn,
          )
        : null;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.save();
    canvas.scale(r * 1.55);
    _shadow.shader = shaders.shadowPenumbra;
    canvas.drawCircle(Offset.zero, 1, _shadow);
    canvas.restore();
    canvas.scale(r);
    _shadow.shader = shaders.shadowCore;
    canvas.drawCircle(Offset.zero, 1, _shadow);
    canvas.restore();
  }

  /// Top-down pawn: dark base ring, shaded body, dome highlight, a tiny
  /// specular dot at the centre and a thin symmetric rim light.
  void _drawPawn(Canvas canvas, _Item item) {
    final pose = item.pose;
    final opacity = (pose?.opacity ?? 1) * (1 - item.dim);
    final ground = Offset(item.pos.x, item.pos.y);
    // Height is already inside the pose scale; never a Y offset.
    final r = baseRadius * item.scale * (pose?.scale ?? 1);

    final faded = opacity < 1;
    if (faded) {
      canvas.saveLayer(
        Rect.fromCircle(center: ground, radius: 1.2),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }

    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    // A captured token flips like a coin: its width shrinks, its height
    // does not.
    canvas.scale(r * (pose?.flipX ?? 1), r);
    _fill
      ..shader = null
      ..color = palette.seatDark(item.seat);
    canvas.drawCircle(Offset.zero, 1, _fill);
    _fill.shader = shaders.body[item.seat];
    canvas.drawCircle(Offset.zero, 0.78, _fill);
    _fill.shader = shaders.dome[item.seat];
    canvas.drawCircle(Offset.zero, 0.52, _fill);
    canvas.drawCircle(Offset.zero, 0.09, _specular);
    canvas.drawCircle(Offset.zero, 0.94, _rim);
    canvas.restore();

    if (faded) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(TokenLayerPainter oldDelegate) => true;
}
