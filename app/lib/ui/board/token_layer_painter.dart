import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/frame_stats.dart';
import 'package:ludo/ui/core/fx.dart';
import 'package:ludo/ui/core/fx_scene.dart';
import 'package:ludo/ui/core/move_plan.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/pulse.dart';
import 'package:ludo/ui/core/revert_plan.dart';
import 'package:ludo/ui/core/token_look.dart';
import 'package:ludo/ui/core/token_timeline.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';

/// Which of the three stacked layers a [TokenLayerPainter] draws. Each has its
/// own `RepaintBoundary` in the board view: [under] (blockade tiles, legal-move
/// glow and rings, pocket glows), [tokens] (shadows, pawns, stack badges) and
/// [over] (dust, shockwave and ripple rings, sparks, the finish ring).
enum TokenLayerPart { under, tokens, over }

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
    this.restLift,
  );

  final int seat;
  final int index;
  final Pt pos;
  final TokenPose? pose;
  final double scale;
  final _Layer layer;

  /// Opacity lost to the "no legal move" dim (`0..1`).
  final double dim;

  /// Idle height (cells) of a token that can move (0 for every other).
  final double restLift;
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
    this.part = TokenLayerPart.tokens,
  }) : super(repaint: game.clock);

  final GameController game;
  final LudoPalette palette;
  final TokenShaders shaders;
  final TokenLayerPart part;

  /// Pawn base-ring radius at scale 1 (grid cells).
  static const double baseRadius = TokenLook.baseRadius;

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
    final revert = game.revert;
    final revertT = now - game.revertStartMs;

    if (part == TokenLayerPart.under) {
      _paintUnder(canvas, now, state);
    } else if (part == TokenLayerPart.tokens) {
      _paintTokens(canvas, now, state, plan, planT, revert, revertT);
    } else {
      _paintOver(canvas, now, plan, planT);
    }

    canvas.restore();
    PaintProbe.stop(probe);
  }

  /// Blockade tiles, legal-move glow and rings, destination markers and the
  /// pocket glows: everything that sits under the pawns.
  void _paintUnder(Canvas canvas, double now, GameState state) {
    _drawBlockades(canvas, now, state);

    // Legal-move glow sits under everything.
    if (game.phase == GamePhase.awaitingMove) {
      final pulse = PulseSample.at(now, game.spec);
      for (final move in game.glowMoves) {
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

    _drawVariants(canvas, now);
    _drawGlows(canvas, now);
  }

  /// Tokens that can move this roll (both tokens of a moving blockade).
  Set<int> _movableKeys() {
    if (game.phase != GamePhase.awaitingMove) {
      return const {};
    }
    return {
      for (final m in game.glowMoves) ...[
        m.owner * tokensPerSeat + m.tokenIndex,
        if (m.isUnit) m.owner * tokensPerSeat + m.partnerIndex,
      ],
    };
  }

  /// Shadows, pawns and stack badges.
  void _paintTokens(
    Canvas canvas,
    double now,
    GameState state,
    MoveAnimationPlan? plan,
    double planT,
    RevertAnimation? revert,
    double revertT,
  ) {
    final movable = _movableKeys();
    final idleLift =
        movable.isEmpty ? 0.0 : PulseSample.movableLift(now, game.spec);
    final dimAmount = game.noMoveSeat == null
        ? 0.0
        : noMoveDim(now, game.noMoveMs, game.spec) * game.spec.noMoveDimAmount;

    // Stable seat/index order; no row sorting (a "lower row is nearer" rule
    // is wrong for the players sitting at the top).
    final items = <_Item>[];
    for (final seat in state.activeSeats) {
      for (var i = 0; i < tokensPerSeat; i++) {
        final pose =
            plan?.poseOf(seat, i, planT) ?? revert?.poseOf(seat, i, revertT);
        var scale = game.restScales[seat][i];
        var layer = _Layer.resting;
        if (pose != null) {
          final isMover = plan != null &&
              seat == plan.owner &&
              (i == plan.tokenIndex || i == plan.partnerIndex);
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
          pose == null && movable.contains(seat * tokensPerSeat + i)
              ? idleLift
              : 0,
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

    if (plan == null && revert == null) {
      _drawBadges(canvas, state);
    }
  }

  /// Dust, shockwave and ripple rings, sparks and the finish ring, over the
  /// pawns.
  void _paintOver(
    Canvas canvas,
    double now,
    MoveAnimationPlan? plan,
    double planT,
  ) {
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
  }

  final Map<int, TextPainter> _digits = {};
  final Paint _badge = Paint();

  /// Count badge on every cell that holds [TokenLook.badgeFrom] tokens or
  /// more (any seats): a palette-coloured pill with the number.
  void _drawBadges(Canvas canvas, GameState state) {
    final counts = <String, (Pt, int)>{};
    for (final seat in state.activeSeats) {
      for (var i = 0; i < tokensPerSeat; i++) {
        final position = state.tokens[seat][i];
        if (!isOnTrack(position) && !isInHomeColumn(position)) {
          continue;
        }
        final c = _geo.cellCenter(seat, position, i);
        final key = '${c.x},${c.y}';
        final prev = counts[key];
        counts[key] = (c, (prev?.$2 ?? 0) + 1);
      }
    }
    for (final (c, n) in counts.values) {
      if (!TokenLook.showBadge(n)) {
        continue;
      }
      final centre = Offset(
        c.x + TokenLook.badgeOffset,
        c.y - TokenLook.badgeOffset,
      );
      _badge.color = palette.text;
      canvas.drawCircle(centre, TokenLook.badgeRadius, _badge);
      final tp = _digits.putIfAbsent(
        n,
        () => TextPainter(
          text: TextSpan(
            text: '$n',
            style: TextStyle(
              color: palette.background,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
      // Laid out at 30 px and drawn scaled, so glyphs stay crisp.
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(0.0125);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  /// Pocket glow of a token that just reached home (under the pawns).
  static const BoardGeometry _geo = BoardGeometry();
  final Paint _wallFill = Paint();
  final Paint _wallEdge = Paint()..style = PaintingStyle.stroke;

  /// Every blockade on the board is marked on its square: a tinted, outlined
  /// tile in the owner's colour with a thin bright inner frame that breathes
  /// slowly, so a wall reads at a glance and tokens of one player are
  /// clearly a unit.
  void _drawBlockades(Canvas canvas, double now, GameState state) {
    final blockades = Engine.blockades(state);
    if (blockades.isEmpty) {
      return;
    }
    final breath = game.spec.reducedMotion
        ? 0.5
        : 0.5 + 0.5 * math.sin(now / 520 * math.pi);
    for (final b in blockades) {
      final c = _geo.trackCell(b.square);
      final color = palette.seatLight(b.seat);
      final outer = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(c.x, c.y), width: 0.96, height: 0.96),
        const Radius.circular(0.2),
      );
      _wallFill.color = palette.seat[b.seat].withAlpha(70);
      canvas.drawRRect(outer, _wallFill);
      _wallEdge
        ..strokeWidth = 0.11
        ..color = color.withAlpha(215);
      canvas.drawRRect(outer, _wallEdge);
      _wallEdge
        ..strokeWidth = 0.035
        ..color = const Color(0xFFFFFFFF)
            .withAlpha((70 + 110 * breath).round().clamp(0, 255));
      canvas.drawRRect(outer.deflate(0.17), _wallEdge);
    }
  }

  /// Destination markers of a token that can move in more than one way: a
  /// ring with one dot for the single token, two dots for the whole blockade.
  void _drawVariants(Canvas canvas, double now) {
    if (game.variants.isEmpty || game.phase != GamePhase.awaitingMove) {
      return;
    }
    final pulse = PulseSample.at(now, game.spec);
    for (var k = 0; k < game.variants.length; k++) {
      final move = game.variants[k];
      final p = game.variantPoints[k];
      final center = Offset(p.x, p.y);
      final color = palette.seatLight(move.owner);
      _ring
        ..strokeWidth = 0.09
        ..color = color.withAlpha((pulse.opacity * 255).round().clamp(0, 255));
      canvas.drawCircle(center, pulse.radius, _ring);
      _spark.color = color;
      if (move.isUnit) {
        canvas.drawCircle(center.translate(-0.2, 0), 0.19, _spark);
        canvas.drawCircle(center.translate(0.2, 0), 0.19, _spark);
      } else {
        canvas.drawCircle(center, 0.24, _spark);
      }
    }
  }

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
        case FxKind.wall:
          color = palette.seatLight(r.seat);
          width = 0.16;
        case FxKind.yardExit:
        case FxKind.ripple:
          color = palette.seatLight(r.seat);
          width = 0.07;
        case FxKind.nudge:
          // The "not allowed" ring is the Red seat's colour of the palette.
          color = palette.seat[0];
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

  /// Centred contact core + penumbra. In the air the shadow widens, fades and
  /// drifts away from the board centre (radially symmetric parallax).
  void _drawShadow(Canvas canvas, _Item item) {
    final pose = item.pose;
    final lift = pose?.lift ?? item.restLift;
    final poseScale = pose?.scale ?? 1;
    // The pose scale folds in height; the shadow keeps only the press / finish
    // shrink and handles height itself. A resting token (idle lift) has no
    // pose scale to take out.
    final onGround =
        pose == null ? 1.0 : poseScale / (1 + game.spec.liftScaleGain * lift);
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
    canvas.scale(r * TokenLook.shadowPenumbraScale);
    _shadow.shader = shaders.shadowPenumbra;
    canvas.drawCircle(Offset.zero, 1, _shadow);
    canvas.restore();
    canvas.scale(r * TokenLook.shadowCoreScale);
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
    final r = baseRadius *
        item.scale *
        (pose?.scale ?? 1 + game.spec.liftScaleGain * item.restLift);

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
