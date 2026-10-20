import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/seeded.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../theme/palette.dart';

/// Radius of the board's own rounded corners (grid units).
const double boardCornerRadius = 0.4;

/// Paints the procedural wooden frame in framed-board units: the square
/// `[0, framedCells]` with the 15 x 15 grid starting at `frameCells`.
///
/// Overhead light, so everything is symmetric: a radial base gradient (no
/// top-left bias), grain strokes along each side, mitred corners and one dark
/// outer plus one light inner hairline. It is meant to be baked into the
/// cached static layer; nothing here runs per frame.
void paintWoodFrame(Canvas canvas, LudoPalette palette) {
  const f = TableLayout.frameCells;
  const w = TableLayout.framedCells;
  const square = Rect.fromLTWH(0, 0, w, w);
  final outer = RRect.fromRectAndRadius(
    square,
    const Radius.circular(boardCornerRadius + f),
  );
  final inner = RRect.fromRectAndRadius(
    const Rect.fromLTWH(f, f, w - 2 * f, w - 2 * f),
    const Radius.circular(boardCornerRadius),
  );
  final ring = Path()
    ..fillType = PathFillType.evenOdd
    ..addRRect(outer)
    ..addRRect(inner);

  canvas.save();
  canvas.clipPath(ring);

  // Base: lighter toward the middle of each side, darker in the corners.
  canvas.drawRect(
    square,
    Paint()
      ..shader = RadialGradient(
        radius: 0.72,
        colors: [palette.woodLight, palette.woodDark],
        stops: const [0.55, 1.0],
      ).createShader(square),
  );

  // Grain: 10 strokes per side, deterministic, clipped to the mitred band.
  final rnd = Seeded(0x700D);
  final grain = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  for (var side = 0; side < 4; side++) {
    canvas.save();
    canvas.translate(w / 2, w / 2);
    canvas.rotate(side * math.pi / 2);
    canvas.translate(-w / 2, -w / 2);
    canvas.clipPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w - f, f)
        ..lineTo(f, f)
        ..close(),
    );
    for (var i = 0; i < 10; i++) {
      final y = rnd.range(0.04, f - 0.04);
      final x0 = rnd.range(-0.5, w * 0.55);
      final x1 = x0 + rnd.range(w * 0.25, w * 0.75);
      final bend = rnd.spread(0.03);
      final dark = rnd.next() < 0.6;
      grain
        ..strokeWidth = rnd.range(0.012, 0.032)
        ..color = (dark ? palette.woodGrainDark : palette.woodGrainLight)
            .withAlpha(rnd.range(26, 62).round());
      canvas.drawPath(
        Path()
          ..moveTo(x0, y)
          ..quadraticBezierTo((x0 + x1) / 2, y + bend, x1, y),
        grain,
      );
    }
    canvas.restore();
  }

  // Mitre seams.
  final seam = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.02
    ..color = palette.woodGrainDark.withAlpha(110);
  canvas.drawLine(const Offset(0, 0), const Offset(f, f), seam);
  canvas.drawLine(const Offset(w, 0), const Offset(w - f, f), seam);
  canvas.drawLine(const Offset(w, w), const Offset(w - f, w - f), seam);
  canvas.drawLine(const Offset(0, w), const Offset(f, w - f), seam);
  canvas.restore();

  // Bevel: dark hairline outside, light hairline against the board.
  canvas.drawRRect(
    outer.deflate(0.015),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.03
      ..color = palette.woodGrainDark.withAlpha(200),
  );
  canvas.drawRRect(
    inner.inflate(0.015),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.03
      ..color = palette.woodGrainLight.withAlpha(150),
  );
}
