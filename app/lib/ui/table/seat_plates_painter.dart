import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:ludo/ui/core/frame_stats.dart';
import 'package:ludo/ui/core/seat_plates.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';

/// Name plates in the table margins: a seat-colour dot, the player's name and
/// an "n/4 home" chip, turned to face the seat like the toasts (`Fixed`
/// orientation keeps them upright). The plate of the seat on turn has an
/// outline in its colour.
///
/// Text is painted, not a widget, so the rotation is a canvas rotation and
/// nothing rebuilds per frame. The painter repaints on the controller's
/// notifications (turn changes, finished moves), never on the frame clock.
/// All colours come from the palette: text is `palette.text` on the felt (the
/// pair the contrast test checks) and the chip's ink is picked for contrast
/// against its seat colour.
class SeatPlatesPainter extends CustomPainter {
  SeatPlatesPainter({
    required this.game,
    required this.layout,
    required this.palette,
    required this.orientation,
  }) : super(repaint: game);

  final GameController game;
  final TableLayout layout;
  final LudoPalette palette;
  final UiOrientation orientation;

  static final Map<String, TextPainter> _text = {};
  final Paint _fill = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  TextPainter _label(String text, double fontSize, Color color) {
    final key = '$text|${fontSize.round()}|${color.toARGB32()}';
    if (_text.length > 96) {
      _text.clear();
    }
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
        maxLines: 1,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final probe = PaintProbe.start();
    final plates = SeatPlates.compute(layout);
    final active = game.activeSeat;
    for (final plate in plates) {
      if (plate == null || !game.state.isActive(plate.seat)) {
        continue;
      }
      _paintPlate(canvas, plate, plate.seat == active);
    }
    PaintProbe.stop(probe);
  }

  void _paintPlate(Canvas canvas, SeatPlate plate, bool onTurn) {
    final seat = plate.seat;
    final depth = plate.depth;
    final name = game.setup.displayName(seat);
    final home = SeatPlates.homeCount(game.state, seat);
    final fill = palette.seat[seat];
    final ink = fill.computeLuminance() > 0.5
        ? const Color(0xFF1B1B1B)
        : const Color(0xFFFFFFFF);

    final nameLabel = _label(name, depth * 0.5, palette.text);
    final chipLabel = _label(SeatPlates.homeLabel(home), depth * 0.42, ink);
    final dot = depth * 0.38;
    final gap = depth * 0.28;
    final chipW = chipLabel.width + depth * 0.5;
    final chipH = depth * 0.64;
    final group = dot + gap + nameLabel.width + gap * 1.5 + chipW;
    final pillW = group + depth * 0.9;

    // Everything fits the plate: a long name shrinks the whole plate.
    final fit = math.min(1.0, plate.along / pillW);

    final c = plate.box.center;
    canvas.save();
    canvas.translate(c.x, c.y);
    final turns = turnsForEdge(plate.edge);
    canvas.rotate(
      (orientation == UiOrientation.fixed ? 0 : turns) * math.pi / 2,
    );
    canvas.scale(fit);

    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: pillW, height: depth),
      Radius.circular(depth / 2),
    );
    if (onTurn) {
      _fill.color = palette.text.withAlpha(28);
      canvas.drawRRect(pill, _fill);
      _stroke
        ..strokeWidth = math.max(1.5, depth * 0.07)
        ..color = fill;
      canvas.drawRRect(pill, _stroke);
    } else {
      _stroke
        ..strokeWidth = math.max(1, depth * 0.04)
        ..color = palette.text.withAlpha(70);
      canvas.drawRRect(pill, _stroke);
    }

    var x = -group / 2;
    _fill.color = fill;
    canvas.drawCircle(Offset(x + dot / 2, 0), dot / 2, _fill);
    x += dot + gap;
    nameLabel.paint(canvas, Offset(x, -nameLabel.height / 2));
    x += nameLabel.width + gap * 1.5;
    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, -chipH / 2, chipW, chipH),
      Radius.circular(chipH / 2),
    );
    _fill.color = fill;
    canvas.drawRRect(chip, _fill);
    chipLabel.paint(
      canvas,
      Offset(x + (chipW - chipLabel.width) / 2, -chipLabel.height / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SeatPlatesPainter oldDelegate) =>
      oldDelegate.game != game ||
      oldDelegate.layout != layout ||
      oldDelegate.palette != palette ||
      oldDelegate.orientation != orientation;
}
