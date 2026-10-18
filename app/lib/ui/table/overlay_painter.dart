import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/frame_stats.dart';
import 'package:ludo/ui/core/fx.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';

/// Table-space overlay above the docks: toasts at the dock of the seat they
/// are for, game-over rank badges and the win confetti.
///
/// Text is painted (not a `Text` widget) so each seat's notice can be turned
/// to face its player with a plain canvas rotation and so nothing rebuilds per
/// frame. It only samples pure timelines from `lib/ui/core`.
class OverlayPainter extends CustomPainter {
  OverlayPainter({
    required this.game,
    required this.layout,
    required this.palette,
    required this.orientation,
  }) : super(repaint: game.clock);

  final GameController game;
  final TableLayout layout;
  final LudoPalette palette;
  final UiOrientation orientation;

  static const List<String> _ordinals = ['1st', '2nd', '3rd', '4th'];

  static final Map<String, TextPainter> _text = {};
  final Paint _fill = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final probe = PaintProbe.start();
    final now = game.clock.value;
    _toasts(canvas, now);
    if (game.phase == GamePhase.gameOver) {
      _badges(canvas, now);
      _confetti(canvas, now);
    }
    PaintProbe.stop(probe);
  }

  TextPainter _label(String text, double fontSize, Color color) {
    final key = '$text|${fontSize.round()}|${color.toARGB32()}';
    return _text.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  /// Dock-local point (`+y` toward the seat's own edge) in table space.
  Offset _dockPoint(DockLayout dock, double along, double toEdge) {
    final v = rotateQuarterTurns(
      Pt(along, toEdge),
      turnsForEdge(dock.edge),
    );
    return Offset(dock.dieCenter.x + v.x, dock.dieCenter.y + v.y);
  }

  void _toasts(Canvas canvas, double now) {
    final cell = layout.cell;
    for (var seat = 0; seat < 4; seat++) {
      final toast = game.toasts[seat];
      if (toast == null) {
        continue;
      }
      final look = toastLook(now, toast.startMs, game.spec);
      if (look.opacity <= 0.01) {
        continue;
      }
      final dock = layout.docks[seat];
      final label = _label(toast.text, cell * 0.42, const Color(0xFFFFFFFF));
      final w = label.width + cell * 0.7;
      final h = cell * 0.8;
      final at = _dockPoint(dock, 0, cell * 1.35);
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(seatTextTurns(layout, seat, orientation) * math.pi / 2);
      canvas.scale(look.scale);
      final box = Rect.fromCenter(center: Offset.zero, width: w, height: h);
      canvas.saveLayer(
        box.inflate(4),
        Paint()..color = Color.fromRGBO(0, 0, 0, look.opacity),
      );
      _fill.color = const Color(0xE6202024);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(h / 2)),
        _fill,
      );
      _stroke
        ..strokeWidth = math.max(1.5, cell * 0.05)
        ..color = palette.seatLight(seat);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(h / 2)),
        _stroke,
      );
      label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
      canvas.restore();
      canvas.restore();
    }
  }

  void _badges(Canvas canvas, double now) {
    final ranking = game.state.ranking;
    final cell = layout.cell;
    for (var rank = 0;
        rank < ranking.length && rank < _ordinals.length;
        rank++) {
      final scale = rankBadgeScale(
        now,
        game.gameOverMs + 250 + rank * 200,
        game.spec,
      );
      if (scale <= 0.01) {
        continue;
      }
      for (final seat in ranking[rank]) {
        final dock = layout.docks[seat];
        final fill = palette.seat[seat];
        final ink = fill.computeLuminance() > 0.5
            ? const Color(0xFF1B1B1B)
            : const Color(0xFFFFFFFF);
        final label = _label(_ordinals[rank], cell * 0.8, ink);
        final w = label.width + cell * 0.9;
        final h = cell * 1.3;
        final at = Offset(dock.rect.center.x, dock.rect.center.y);
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(seatTextTurns(layout, seat, orientation) * math.pi / 2);
        canvas.scale(scale);
        final shape = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          Radius.circular(h * 0.4),
        );
        _fill.color = fill;
        canvas.drawRRect(shape, _fill);
        _stroke
          ..strokeWidth = math.max(2, cell * (rank == 0 ? 0.12 : 0.07))
          ..color = rank == 0
              ? const Color(0xFFFFC107)
              : const Color(0xFFFFFFFF).withAlpha(200);
        canvas.drawRRect(shape, _stroke);
        label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
        canvas.restore();
      }
    }
  }

  void _confetti(Canvas canvas, double now) {
    final burst = game.confetti;
    if (burst == null) {
      return;
    }
    final pieces = burst.sample(now);
    if (pieces.isEmpty) {
      return;
    }
    final cell = layout.cell;
    final c = layout.board.center;
    for (final p in pieces) {
      canvas.save();
      canvas.translate(c.x + p.pos.x * cell, c.y + p.pos.y * cell);
      canvas.rotate(p.rotation);
      _fill.color = palette.seatLight(p.colorIndex % 4).withAlpha(
            (p.opacity * 255).round().clamp(0, 255),
          );
      final w = p.size * cell;
      canvas.drawRect(Rect.fromLTWH(-w / 2, -w / 4, w, w / 2), _fill);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) => true;
}
