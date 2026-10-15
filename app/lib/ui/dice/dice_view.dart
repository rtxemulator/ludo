import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ludo/ui/core/dice_timeline.dart';

import '../../game/game_controller.dart';
import '../theme/palette.dart';

/// Tappable dice. Animation comes from `DiceTimeline` (pure function of
/// time); this widget only draws the sampled pose.
class DiceView extends StatelessWidget {
  const DiceView({
    super.key,
    required this.game,
    required this.palette,
    this.size = 96,
  });

  final GameController game;
  final LudoPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: game.roll,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: DicePainter(game, palette)),
      ),
    );
  }
}

class DicePainter extends CustomPainter {
  DicePainter(this.game, this.palette) : super(repaint: game.clock);

  final GameController game;
  final LudoPalette palette;

  static const List<Offset> _pip = [
    Offset(-0.5, -0.5), // 0 top-left
    Offset(0.5, -0.5), // 1 top-right
    Offset(-0.5, 0), // 2 mid-left
    Offset(0, 0), // 3 centre
    Offset(0.5, 0), // 4 mid-right
    Offset(-0.5, 0.5), // 5 bottom-left
    Offset(0.5, 0.5), // 6 bottom-right
  ];

  static const Map<int, List<int>> _faces = {
    1: [3],
    2: [0, 6],
    3: [0, 3, 6],
    4: [0, 1, 5, 6],
    5: [0, 1, 3, 5, 6],
    6: [0, 1, 2, 4, 5, 6],
  };

  Shader? _sheen;

  @override
  void paint(Canvas canvas, Size size) {
    final now = game.clock.value;
    final timeline = game.dice;
    final DicePose pose;
    if (game.phase == GamePhase.rolling && timeline != null) {
      pose = timeline.sample(now - game.diceStartMs);
    } else {
      pose = DicePose(face: game.lastRoll ?? 0, angle: 0, scale: 1);
    }

    final s = size.width;
    final color = palette.seat[game.diceSeat];
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.rotate(pose.angle);
    canvas.scale(pose.scale);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: s * 0.84,
      height: s * 0.84,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.16));
    canvas.drawRRect(
      rrect.shift(Offset(0, s * 0.03)),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawRRect(rrect, Paint()..color = color);
    _sheen ??= LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [Color(0x55FFFFFF), Color(0x00FFFFFF), Color(0x22000000)],
    ).createShader(rect);
    canvas.drawRRect(rrect, Paint()..shader = _sheen);

    final pips = _faces[pose.face];
    if (pips != null) {
      final paint = Paint()..color = const Color(0xFFFFFFFF);
      for (final i in pips) {
        canvas.drawCircle(
          Offset(
              _pip[i].dx * rect.width * 0.62, _pip[i].dy * rect.height * 0.62),
          s * 0.065,
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DicePainter oldDelegate) => true;
}
