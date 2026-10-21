import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/bank_tray.dart';
import 'package:ludo/ui/core/dice3d.dart' show pipLayout;
import 'package:ludo/ui/core/frame_stats.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';

/// Banked rolls: the roll trays. Draws the die chips of every seat beside
/// its dock; it only *samples* `BankTray.pose` (a pure function of time in
/// `lib/ui/core`) and draws what it says. Nothing is drawn when the rule is
/// off, because then the tray is always empty.
///
/// A tray is laid out in the dock's frame (`+x` along the player's edge,
/// `+y` toward it), turned to the seat by its edge's quarter turns; the chip
/// *faces* turn with `seatTextTurns`, like every other text for that seat.
/// The light is overhead: chips have a centred shadow, lift is scale.
class TrayPainter extends CustomPainter {
  TrayPainter({
    required this.game,
    required this.layout,
    required this.palette,
    required this.orientation,
  }) : super(repaint: game.clock);

  final GameController game;
  final TableLayout layout;
  final LudoPalette palette;
  final UiOrientation orientation;

  static const double _radius = 0.16;
  static final RRect _face = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-0.5, -0.5, 1, 1),
    const Radius.circular(_radius),
  );
  static final Shader _shadowShader = const RadialGradient(
    colors: [Color(0x80000000), Color(0x00000000)],
    stops: [0.5, 1.0],
  ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));

  final Paint _fill = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  final Paint _shadow = Paint()..shader = _shadowShader;
  final List<bool> _has = List.filled(_seats, false);

  static const int _seats = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final tray = game.tray;
    if (tray.isEmpty) {
      return;
    }
    final probe = PaintProbe.start();
    final now = game.clock.value;
    final spec = game.spec;

    _has.fillRange(0, _seats, false);
    for (final chip in tray.chips) {
      _has[chip.seat] = true;
    }
    for (var seat = 0; seat < _seats; seat++) {
      if (_has[seat]) {
        _mat(canvas, seat);
      }
    }

    // Resting chips, then the selected one on top, then chips in flight.
    for (var pass = 0; pass < 3; pass++) {
      for (final chip in tray.chips) {
        final select = chip.leaving ? 0.0 : tray.selectAmount(chip, now, spec);
        final mine = chip.leaving
            ? 2
            : select > 0.01
                ? 1
                : 0;
        if (mine != pass) {
          continue;
        }
        final pose = tray.pose(chip, now, spec);
        if (pose != null) {
          _chip(canvas, chip, pose);
        }
      }
    }
    PaintProbe.stop(probe);
  }

  /// The faint shelf under a seat's chips (only for a tray outside the dock;
  /// an inner tray sits on the dock's own mat).
  void _mat(Canvas canvas, int seat) {
    final dock = layout.docks[seat];
    if (!dock.trayOuter) {
      return;
    }
    final cell = layout.cell;
    final box = Rect.fromLTWH(
      dock.tray.left,
      dock.tray.top,
      dock.tray.width,
      dock.tray.height,
    ).deflate(cell * 0.05);
    final rrect = RRect.fromRectAndRadius(box, Radius.circular(cell * 0.4));
    _fill
      ..shader = null
      ..colorFilter = null
      ..color = palette.seat[seat].withAlpha(18);
    canvas.drawRRect(rrect, _fill);
    _stroke
      ..strokeWidth = math.max(1.0, cell * 0.05)
      ..color = palette.seat[seat].withAlpha(60);
    canvas.drawRRect(rrect, _stroke);
  }

  void _chip(Canvas canvas, TrayChip chip, ChipPose pose) {
    final dock = layout.docks[chip.seat];
    final cell = layout.cell;
    final px = dock.chipSize;
    final spec = game.spec;

    // Opacity: pop / exit, and a chip that cannot be spent right now is
    // dimmed while the bank is being spent.
    var opacity = pose.opacity;
    final c = game.choice;
    if (!chip.leaving &&
        c != null &&
        game.phase == GamePhase.awaitingMove &&
        chip.seat == game.state.currentSeat &&
        !c.isPlayable(chip.slot)) {
      opacity *= spec.tray.dimOpacity;
    }
    if (opacity <= 0.01) {
      return;
    }
    final a = (opacity * 255).round().clamp(0, 255);

    // Position: the tray's frame turned to the edge, then (for a spent chip)
    // on toward its token.
    final local = rotateQuarterTurns(
      Pt(pose.x * px, pose.y * px),
      turnsForEdge(dock.edge),
    );
    var cx = dock.trayCenter.x + local.x;
    var cy = dock.trayCenter.y + local.y;
    final target = pose.target;
    if (target != null && pose.flight > 0) {
      final tx = layout.board.left + target.x * cell;
      final ty = layout.board.top + target.y * cell;
      cx += (tx - cx) * pose.flight;
      cy += (ty - cy) * pose.flight;
    }

    final edge = px * pose.scale;
    final turns = seatTextTurns(layout, chip.seat, orientation);

    canvas.save();
    canvas.translate(cx, cy);

    // Shadow: centred, wider (and a little fainter) the higher the chip is.
    final lift = math.max(0.0, pose.scale - 1);
    _shadow.colorFilter = ColorFilter.mode(
      Color.fromRGBO(0, 0, 0, (opacity * (0.9 - 0.4 * lift)).clamp(0.0, 1.0)),
      BlendMode.dstIn,
    );
    canvas.save();
    canvas.scale(edge * 0.68);
    canvas.drawCircle(Offset.zero, 1, _shadow);
    canvas.restore();

    canvas.rotate(turns * math.pi / 2 + pose.angle);
    canvas.scale(edge);

    if (pose.select > 0.01) {
      final glow = palette.seatLight(chip.seat);
      _fill
        ..shader = null
        ..colorFilter = null
        ..color = glow.withAlpha((pose.select * opacity * 70).round());
      canvas.drawCircle(Offset.zero, 0.95, _fill);
      _stroke
        ..strokeWidth = 0.07
        ..color = glow.withAlpha((pose.select * opacity * 230).round());
      canvas.drawRRect(_face.inflate(0.1), _stroke);
    }

    _fill
      ..shader = null
      ..colorFilter = null
      ..color = palette.seat[chip.seat].withAlpha(a);
    canvas.drawRRect(_face, _fill);
    _stroke
      ..strokeWidth = 0.035
      ..color = Color.fromARGB((0x4D * opacity).round(), 255, 255, 255);
    canvas.drawRRect(_face, _stroke);
    _fill.color = Color.fromARGB(a, 255, 255, 255);
    for (final p in pipLayout(chip.value)) {
      canvas.drawCircle(Offset(p.x, p.y), 0.085, _fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TrayPainter oldDelegate) => true;
}
