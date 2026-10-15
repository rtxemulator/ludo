import 'dart:ui';

import 'package:flutter/painting.dart';

import 'palette.dart';

/// Gradient shaders (they are GPU shaders: `Paint.shader`) created once per
/// palette and reused every frame. All are defined on a unit circle; the
/// painter scales the canvas to the real radius.
class TokenShaders {
  TokenShaders(LudoPalette palette)
      : body = [
          for (var s = 0; s < 4; s++)
            RadialGradient(
              center: const Alignment(-0.35, -0.45),
              radius: 1.0,
              colors: [
                palette.seatLight(s),
                palette.seat[s],
                palette.seatDark(s)
              ],
              stops: const [0.0, 0.55, 1.0],
            ).createShader(_unit),
        ],
        glow = [
          for (var s = 0; s < 4; s++)
            RadialGradient(
              colors: [
                palette.seat[s].withAlpha(150),
                palette.seat[s].withAlpha(0),
              ],
            ).createShader(_unit),
        ];

  static final Rect _unit = Rect.fromCircle(center: Offset.zero, radius: 1);

  /// 3D-looking token body per seat.
  final List<Shader> body;

  /// Soft legal-move glow per seat (fixed alpha; only its size pulses).
  final List<Shader> glow;
}
