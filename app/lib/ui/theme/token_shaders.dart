import 'package:flutter/painting.dart';

import 'palette.dart';

/// Gradient shaders (they are GPU shaders: `Paint.shader`) created once per
/// palette and reused every frame. All are defined on a unit circle (radius 1
/// = the pawn's base ring); the painter scales the canvas to the real radius.
///
/// `RadialGradient.radius` is a fraction of the rect's *shortest side*, and
/// the unit rect is 2 wide, so a gradient reaching radius `r` units uses
/// `radius: r / 2`.
class TokenShaders {
  TokenShaders(LudoPalette palette)
      : body = [
          for (var s = 0; s < 4; s++)
            RadialGradient(
              radius: 0.39, // body disc, 0.78 units
              colors: [
                Color.lerp(palette.seat[s], const Color(0xFFFFFFFF), 0.24)!,
                palette.seat[s],
                Color.lerp(palette.seat[s], const Color(0xFF000000), 0.18)!,
              ],
              stops: const [0.0, 0.62, 1.0],
            ).createShader(_unit),
        ],
        dome = [
          for (var s = 0; s < 4; s++)
            RadialGradient(
              radius: 0.26, // dome, 0.52 units
              colors: [
                palette.seatLight(s).withAlpha(235),
                palette.seatLight(s).withAlpha(40),
              ],
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
        ],
        shadowCore = const RadialGradient(
          colors: [Color(0x78000000), Color(0x5A000000), Color(0x00000000)],
          stops: [0.0, 0.62, 1.0],
        ).createShader(_unit),
        shadowPenumbra = const RadialGradient(
          colors: [Color(0x2E000000), Color(0x00000000)],
          stops: [0.35, 1.0],
        ).createShader(_unit);

  static final Rect _unit = Rect.fromCircle(center: Offset.zero, radius: 1);

  /// Pawn body per seat: radial, lighter at the centre (symmetric).
  final List<Shader> body;

  /// Pawn dome highlight per seat.
  final List<Shader> dome;

  /// Soft legal-move glow per seat (fixed alpha; only its size pulses).
  final List<Shader> glow;

  /// Tight, darker shadow right under the pawn.
  final Shader shadowCore;

  /// Wide, light shadow around it.
  final Shader shadowPenumbra;
}
