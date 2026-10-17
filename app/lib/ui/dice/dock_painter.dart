import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/dice3d.dart';
import 'package:ludo/ui/core/dock_look.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/rot3.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';

/// Draws the four docks: a faint mat per seat and its die (live, tumbling,
/// ghost). It only *samples* `Dice3dTimeline` and `DockLook` (pure functions
/// of time in `lib/ui/core`) and draws what they say.
///
/// Everything is drawn in the dock's own frame: `+y` points at the player's
/// own table edge (the "hand"), so the canvas is turned by that edge's quarter
/// turns and each seat sees its die thrown from its side toward the board.
/// The light is overhead: the shadow is centred and only drifts radially away
/// from the board centre while the die is in the air; height is scale.
class DockPainter extends CustomPainter {
  DockPainter({
    required this.game,
    required this.layout,
    required this.palette,
  }) : super(repaint: game.clock);

  final GameController game;
  final TableLayout layout;
  final LudoPalette palette;

  /// Shadow drift away from the board centre per cell of height.
  static const double _drift = 0.12;

  /// Shadow radius relative to the die edge.
  static const double _shadowReach = 0.62;

  static final Mat3 _fresh = finalOrientation(1);
  static final RRect _face = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-0.515, -0.515, 1.03, 1.03),
    const Radius.circular(0.15),
  );
  static final Shader _shadowShader = const RadialGradient(
    colors: [Color(0x85000000), Color(0x00000000)],
    stops: [0.5, 1.0],
  ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));

  final Paint _fill = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  final Paint _shadow = Paint()..shader = _shadowShader;
  final Paint _pip = Paint();
  final Paint _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.035
    ..color = const Color(0x4DFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final now = game.clock.value;
    final active = game.activeSeat;
    // The seat on turn is drawn last so a tumbling die is on top.
    for (var seat = 0; seat < 4; seat++) {
      if (seat != active) {
        _paintDock(canvas, seat, now, active);
      }
    }
    if (active != null) {
      _paintDock(canvas, active, now, active);
    }
  }

  void _paintDock(Canvas canvas, int seat, double now, int? active) {
    final dock = layout.docks[seat];
    final spec = game.spec;
    final cell = layout.cell;
    final turns = turnsForEdge(dock.edge);
    final live = DockLook.live(
      active: seat == active,
      wasActive: seat == game.prevActiveSeat,
      sinceMs: now - game.activeSinceMs,
      spec: spec,
    );

    // Mat.
    final mat = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        dock.rect.left,
        dock.rect.top,
        dock.rect.width,
        dock.rect.height,
      ),
      Radius.circular(cell * 0.5),
    );
    _fill
      ..shader = null
      ..color = palette.seat[seat].withAlpha((16 + 26 * live).round());
    canvas.drawRRect(mat, _fill);
    _stroke
      ..strokeWidth = math.max(1.5, cell * 0.07)
      ..color = palette.seat[seat].withAlpha((50 + 110 * live).round());
    canvas.drawRRect(mat, _stroke);
    final pulse = DockLook.pulse(now, game.dockPulseMs[seat], spec);
    if (pulse > 0) {
      _stroke
        ..strokeWidth = cell * 0.12
        ..color = palette.seatLight(seat).withAlpha((pulse * 210).round());
      canvas.drawRRect(mat.inflate((1 - pulse) * cell * 0.25), _stroke);
    }

    // Which die, and in what pose.
    final roll = game.dice;
    Dice3dTimeline? tumble;
    if (roll != null &&
        seat == game.rollerSeat &&
        now - game.diceStartMs < roll.durationMs) {
      tumble = roll;
    }
    final Dice3dPose pose;
    final DockLook look;
    if (tumble != null) {
      pose = tumble.sample(now - game.diceStartMs);
      look = DockLook.sample(live: 1, idle: false, tMs: now, spec: spec);
    } else {
      final last = game.seatDice[seat];
      if (last == null && seat != active) {
        return;
      }
      pose = Dice3dPose(
        rotation: last?.finalRotation ?? _fresh,
        offset: last?.landing ?? Pt.zero,
        height: 0,
        scale: 1,
        opacity: 1,
        shadowScale: 1,
        shadowOpacity: 1,
        ringRadius: 0,
        ringOpacity: 0,
        goldOpacity: 0,
      );
      look = DockLook.sample(
        live: live,
        idle: seat == active && game.phase == GamePhase.awaitingRoll,
        tMs: now,
        spec: spec,
      );
    }

    // Ground position on screen: dock centre + the dock-local offset turned
    // to this seat.
    final local = rotateQuarterTurns(
      Pt(pose.offset.x * cell, pose.offset.y * cell),
      turns,
    );
    final ground = Offset(
      dock.dieCenter.x + local.x,
      dock.dieCenter.y + local.y,
    );
    final alpha = look.opacity * pose.opacity;
    final edge = dock.dieSize * pose.scale * look.scale;

    // Halos: idle (waiting to be rolled) and the six flash.
    if (look.halo > 0) {
      _halo(
        canvas,
        ground,
        dock.dieSize * 1.1,
        palette.seatLight(seat),
        look.halo,
      );
    }
    if (pose.goldOpacity > 0) {
      _halo(
        canvas,
        ground,
        dock.dieSize * 1.15,
        const Color(0xFFFFC107),
        0.7 * pose.goldOpacity,
      );
    }

    // Shadow: centred, widening and fading with height, drifting radially
    // away from the board centre.
    final bc = layout.board.center;
    var sx = ground.dx;
    var sy = ground.dy;
    final vx = sx - bc.x;
    final vy = sy - bc.y;
    final len = math.sqrt(vx * vx + vy * vy);
    if (pose.height > 0 && len > 1e-6) {
      sx += vx / len * _drift * pose.height * cell;
      sy += vy / len * _drift * pose.height * cell;
    }
    final shadowAlpha = pose.shadowOpacity * alpha;
    if (shadowAlpha > 0.01) {
      _shadow.colorFilter = shadowAlpha < 0.999
          ? ColorFilter.mode(
              Color.fromRGBO(0, 0, 0, shadowAlpha),
              BlendMode.dstIn,
            )
          : null;
      canvas.save();
      canvas.translate(sx, sy);
      canvas.scale(dock.dieSize * _shadowReach * pose.shadowScale * look.scale);
      canvas.drawCircle(Offset.zero, 1, _shadow);
      canvas.restore();
    }

    // The cube.
    var base = palette.seat[seat];
    if (look.desaturate > 0) {
      final hsl = HSLColor.fromColor(base);
      base =
          hsl.withSaturation(hsl.saturation * (1 - look.desaturate)).toColor();
    }
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.rotate(turns * math.pi / 2);
    final faded = alpha < 0.999;
    if (faded) {
      canvas.saveLayer(
        Rect.fromCircle(center: Offset.zero, radius: edge * 1.2),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }
    _drawCube(canvas, pose.rotation, edge, base);
    if (faded) {
      canvas.restore();
    }
    canvas.restore();

    // Result ring of the reveal.
    if (pose.ringOpacity > 0) {
      _stroke
        ..strokeWidth = cell * 0.08
        ..color = palette
            .seatLight(seat)
            .withAlpha((pose.ringOpacity * 255).round().clamp(0, 255));
      canvas.drawCircle(ground, pose.ringRadius * cell, _stroke);
    }
  }

  void _halo(
    Canvas canvas,
    Offset centre,
    double radius,
    Color colour,
    double strength,
  ) {
    _fill
      ..color = const Color(0xFF000000)
      ..shader = RadialGradient(
        colors: [
          colour.withAlpha((strength * 255).round().clamp(0, 255)),
          colour.withAlpha(0),
        ],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawCircle(centre, radius, _fill);
    _fill.shader = null;
  }

  /// At most three faces are turned toward the viewer; each is a rounded
  /// square drawn through an affine transform, with its pips.
  void _drawCube(Canvas canvas, Mat3 rotation, double edge, Color base) {
    for (final face in visibleFaces(rotation)) {
      final m = Float64List(16)
        ..[0] = face.ux * edge
        ..[1] = face.uy * edge
        ..[4] = face.vx * edge
        ..[5] = face.vy * edge
        ..[10] = 1
        ..[12] = face.cx * edge
        ..[13] = face.cy * edge
        ..[15] = 1;
      canvas.save();
      canvas.transform(m);
      _fill
        ..shader = null
        ..color = Color.lerp(const Color(0xFF000000), base, face.shade)!;
      canvas.drawRRect(_face, _fill);
      canvas.drawRRect(_face, _edge);
      _pip.color = Color.lerp(
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
        0.7 + 0.3 * face.shade,
      )!;
      for (final p in pipLayout(face.value)) {
        canvas.drawCircle(Offset(p.x, p.y), 0.085, _pip);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(DockPainter oldDelegate) => true;
}
