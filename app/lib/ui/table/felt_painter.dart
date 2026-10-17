import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/seeded.dart';

import '../theme/palette.dart';

/// The table: felt with a vignette and fine speckle, plus a soft centred
/// shadow under the wooden frame (overhead light, so no offset).
///
/// Static; the table view wraps it in a `RepaintBoundary`.
class FeltPainter extends CustomPainter {
  FeltPainter({required this.palette, required this.frame});

  final LudoPalette palette;

  /// The framed board in this painter's own coordinates.
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final reach =
        math.sqrt(size.width * size.width + size.height * size.height) /
            2 /
            size.shortestSide;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: reach,
          colors: [palette.feltCentre, palette.feltEdge],
        ).createShader(rect),
    );

    // Fibres: two sets of tiny dots, deterministic.
    final rnd = Seeded(0xFE17);
    final count = (size.width * size.height / 1400).clamp(200, 1800).round();
    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < count; i++) {
      final p = Offset(
        rnd.range(0, size.width),
        rnd.range(0, size.height),
      );
      (i.isEven ? light : dark).add(p);
    }
    final dot = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(
        PointMode.points, light, dot..color = const Color(0x0DFFFFFF));
    canvas.drawPoints(
        PointMode.points, dark, dot..color = const Color(0x12000000));

    // Frame shadow.
    final spread = frame.width * 0.012;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        frame.inflate(spread),
        Radius.circular(frame.width * 0.055),
      ),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, frame.width * 0.014),
    );
  }

  @override
  bool shouldRepaint(FeltPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.frame != frame;
}
