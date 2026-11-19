import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/board_polish.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../theme/palette.dart';
import 'wood_frame.dart';

/// Static board layer: wooden frame, yards, track, home columns, safe-square
/// stars, chevrons and the centre. Drawn in grid units (1 unit = 1 cell) onto
/// a canvas the size of the *framed* board. Wrapped in a `RepaintBoundary` by
/// the table view, so the whole thing (frame and board) is rasterised once
/// per size or theme change and never during play. Anything that changes
/// during play (the "tokens home" pips) lives in its own dynamic layer.
///
/// Look (UI/UX doc section 5 and the polish pass): cells are rounded tiles
/// with a 1-2 px gap, each with a faint symmetric bevel (one overhead light,
/// no lit corner); start squares and home columns carry chevrons toward the
/// centre; the yard's inner panel is recessed. All colours come from the
/// active [LudoPalette].
class BoardPainter extends CustomPainter {
  BoardPainter(this.palette);

  final LudoPalette palette;

  static const BoardGeometry _geo = BoardGeometry();

  static Offset _o(Pt p) => Offset(p.x, p.y);

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  @override
  void paint(Canvas canvas, Size size) {
    final cellPx = size.width / TableLayout.framedCells;
    canvas.save();
    canvas.scale(cellPx);
    paintWoodFrame(canvas, palette);
    canvas.translate(TableLayout.frameCells, TableLayout.frameCells);
    _paintBoard(canvas, BoardPolish.cellGap(cellPx));
    canvas.restore();
  }

  /// One cell tile: rounded, with a faint darker edge and a faint lighter
  /// inner line (symmetric bevel).
  void _tile(Canvas canvas, Offset centre, Color color, double gap) {
    final side = 1 - gap;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: centre, width: side, height: side),
      const Radius.circular(BoardPolish.cellRadius),
    );
    final paint = Paint()..color = color;
    canvas.drawRRect(rrect, paint);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = BoardPolish.bevelWidth
      ..color = Color.lerp(color, _black, BoardPolish.bevelDarken)!;
    canvas.drawRRect(rrect.deflate(BoardPolish.bevelWidth / 2), paint);
    paint.color = Color.lerp(color, _white, BoardPolish.bevelLighten)!;
    canvas.drawRRect(rrect.deflate(BoardPolish.bevelInset), paint);
  }

  /// A chevron on [cell] pointing toward the board centre.
  void _chevron(Canvas canvas, Pt cell, Color color) {
    final pts = BoardPolish.chevronPoints();
    final path = Path()..moveTo(pts[0].x, pts[0].y);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].x, pts[i].y);
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = BoardPolish.chevronStroke
      ..color = color;
    canvas.save();
    canvas.translate(cell.x, cell.y);
    canvas.rotate(BoardPolish.chevronTurns(cell) * math.pi / 2);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _paintBoard(Canvas canvas, double gap) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.04
      ..color = palette.cellLine;
    final fill = Paint()..style = PaintingStyle.fill;

    // Board surface with a very subtle vignette. Everything below is clipped
    // to the rounded board, so only the outer corners are round and the
    // yards meet the path arms flush.
    final boardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 15, 15),
      const Radius.circular(boardCornerRadius),
    );
    canvas.save();
    canvas.clipRRect(boardRect);
    fill
      ..shader = null
      ..color = palette.board;
    canvas.drawRRect(boardRect, fill);
    fill.shader = const RadialGradient(
      radius: 0.85,
      colors: [Color(0x00000000), Color(0x14000000)],
    ).createShader(const Rect.fromLTWH(0, 0, 15, 15));
    canvas.drawRRect(boardRect, fill);
    fill.shader = null;

    // Yards: flush 6 x 6 quadrants (no gap to the path arms), with a recessed
    // inner panel and recessed token spots.
    for (var s = 0; s < 4; s++) {
      final a = BoardGeometry.rotate(const Pt(0, 0), s);
      final b = BoardGeometry.rotate(const Pt(6, 6), s);
      final yard = Rect.fromPoints(_o(a), _o(b));
      fill.color = palette.seat[s];
      canvas.drawRect(yard, fill);
      final panel = RRect.fromRectAndRadius(
        yard.deflate(BoardPolish.yardInset),
        const Radius.circular(0.6),
      );
      fill.color = palette.yardInner;
      canvas.drawRRect(panel, fill);
      // Symmetric recess: a darker line just inside the panel edge and a
      // lighter one just outside it, so the panel reads as sunk into the
      // quadrant under the overhead light.
      line
        ..strokeWidth = BoardPolish.yardRecessWidth
        ..color = Color.lerp(palette.yardInner, _black, 0.18)!;
      canvas.drawRRect(panel.deflate(BoardPolish.yardRecessWidth / 2), line);
      line.color = Color.lerp(palette.seat[s], _white, 0.25)!;
      canvas.drawRRect(panel.inflate(BoardPolish.yardRecessWidth / 2), line);
      for (var i = 0; i < 4; i++) {
        final spot = _o(_geo.yardSpot(s, i));
        fill.color = Color.lerp(palette.yardInner, _black, 0.07)!;
        canvas.drawCircle(spot, BoardPolish.yardSpotRadius, fill);
        fill.color = palette.seat[s].withAlpha(60);
        canvas.drawCircle(spot, BoardPolish.yardSpotRadius, fill);
        line
          ..strokeWidth = 0.05
          ..color = palette.seat[s];
        canvas.drawCircle(spot, BoardPolish.yardSpotRadius, line);
      }
    }
    line
      ..strokeWidth = 0.04
      ..color = palette.cellLine;

    // Track squares: start squares tinted (with a chevron), star squares
    // marked.
    for (var sq = 0; sq < 52; sq++) {
      final p = _geo.trackCell(sq);
      final c = _o(p);
      final isStart = sq % 13 == 0;
      _tile(canvas, c, isStart ? palette.seat[sq ~/ 13] : palette.cell, gap);
      if (isStart) {
        _chevron(canvas, p, palette.onSeat(sq ~/ 13));
      }
      if (sq % 13 == 8) {
        fill.color = palette.seat[sq ~/ 13].withAlpha(230);
        canvas.drawPath(_star(c, 0.34, 0.15), fill);
      }
    }

    // Home columns (chevrons toward the centre).
    for (var s = 0; s < 4; s++) {
      for (var p = 51; p <= 55; p++) {
        final cell = _geo.homeCell(s, p);
        _tile(
          canvas,
          _o(cell),
          Color.alphaBlend(palette.seat[s].withAlpha(200), palette.board),
          gap,
        );
        _chevron(canvas, cell, palette.onSeat(s).withAlpha(190));
      }
    }

    // Centre: one triangle per seat pointing at the middle. The tokens-home
    // pips are drawn on top of it by the dynamic layer.
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
