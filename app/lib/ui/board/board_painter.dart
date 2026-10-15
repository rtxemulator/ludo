import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/pt.dart';

import '../theme/palette.dart';

/// Static board layer: yards, track, home columns, safe-square stars and the
/// centre. Drawn in grid units (1 unit = 1 cell). Wrapped in a
/// `RepaintBoundary` by the board view, so it is rasterised once per size or
/// theme change and never during play.
class BoardPainter extends CustomPainter {
  BoardPainter(this.palette);

  final LudoPalette palette;

  static const BoardGeometry _geo = BoardGeometry();

  static Offset _o(Pt p) => Offset(p.x, p.y);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / BoardGeometry.gridSize);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.04
      ..color = palette.cellLine;
    final fill = Paint()..style = PaintingStyle.fill;

    // Board surface with a very subtle vignette.
    final boardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 15, 15),
      const Radius.circular(0.4),
    );
    fill
      ..shader = null
      ..color = palette.board;
    canvas.drawRRect(boardRect, fill);
    fill.shader = RadialGradient(
      radius: 0.85,
      colors: [
        const Color(0x00000000),
        const Color(0x14000000),
      ],
    ).createShader(const Rect.fromLTWH(0, 0, 15, 15));
    canvas.drawRRect(boardRect, fill);
    fill.shader = null;

    // Yards.
    for (var s = 0; s < 4; s++) {
      final a = BoardGeometry.rotate(const Pt(0, 0), s);
      final b = BoardGeometry.rotate(const Pt(6, 6), s);
      final yard = Rect.fromPoints(_o(a), _o(b));
      fill.color = palette.seat[s];
      canvas.drawRRect(
        RRect.fromRectAndRadius(yard.deflate(0.05), const Radius.circular(0.5)),
        fill,
      );
      fill.color = palette.yardInner;
      canvas.drawRRect(
        RRect.fromRectAndRadius(yard.deflate(1), const Radius.circular(0.6)),
        fill,
      );
      for (var i = 0; i < 4; i++) {
        final spot = _o(_geo.yardSpot(s, i));
        fill.color = palette.seat[s].withAlpha(60);
        canvas.drawCircle(spot, 0.45, fill);
        line.color = palette.seat[s];
        canvas.drawCircle(spot, 0.45, line);
      }
    }
    line.color = palette.cellLine;

    // Track squares: start squares tinted, star squares marked.
    for (var sq = 0; sq < 52; sq++) {
      final c = _o(_geo.trackCell(sq));
      final rect = Rect.fromCenter(center: c, width: 1, height: 1);
      final isStart = sq % 13 == 0;
      fill.color = isStart ? palette.seat[sq ~/ 13] : palette.cell;
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, line);
      if (sq % 13 == 8) {
        fill.color = palette.seat[sq ~/ 13].withAlpha(230);
        canvas.drawPath(_star(c, 0.34, 0.15), fill);
      }
    }

    // Home columns.
    for (var s = 0; s < 4; s++) {
      for (var p = 51; p <= 55; p++) {
        final c = _o(_geo.homeCell(s, p));
        final rect = Rect.fromCenter(center: c, width: 1, height: 1);
        fill.color = palette.seat[s].withAlpha(200);
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, line);
      }
    }

    // Centre: one triangle per seat pointing at the middle.
    for (var s = 0; s < 4; s++) {
      final p0 = _o(BoardGeometry.rotate(const Pt(6, 6), s));
      final p1 = _o(BoardGeometry.rotate(const Pt(6, 9), s));
      final p2 = _o(BoardGeometry.rotate(const Pt(7.5, 7.5), s));
      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      fill.color = palette.seat[s];
      canvas.drawPath(path, fill);
      canvas.drawPath(path, line);
    }

    canvas.restore();
  }

  static Path _star(Offset c, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = c.dx + r * math.cos(a);
      final y = c.dy + r * math.sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
