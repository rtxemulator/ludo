/// Turn focus: how the yard of the seat on turn is marked (polish pass,
/// step 4). Pure Dart, no Flutter.
///
/// The old heavy radial glow darkened some seat colours (yellow turned
/// brownish) and the other yards were washed out, so the board flickered in
/// brightness every turn. Now the seat on turn gets a crisp pulsing ring in
/// the coloured border of its quadrant plus a light *additive* glow on that
/// border, and the other yards are not touched at all.
library;

import 'dart:math' as math;

import 'curves.dart';
import 'motion_spec.dart';

/// What to draw for one yard at one moment. All values are `0..1` strengths
/// except [ringWidth], which is in cells.
class TurnFocusSample {
  const TurnFocusSample({
    required this.ringAlpha,
    required this.ringWidth,
    required this.glowAlpha,
  });

  /// Nothing to draw (the yard is not on turn).
  static const TurnFocusSample none = TurnFocusSample(
    ringAlpha: 0,
    ringWidth: 0,
    glowAlpha: 0,
  );

  final double ringAlpha;
  final double ringWidth;
  final double glowAlpha;

  bool get visible => ringAlpha > 0.01 || glowAlpha > 0.01;
}

class TurnFocus {
  const TurnFocus._();

  /// Breathing period of the ring and the glow.
  static const double periodMs = 1800;

  /// The ring runs along the middle of the quadrant's coloured border (the
  /// panel is inset 1 cell from the quadrant), so it never touches the
  /// panel, the path arms or the pawns.
  static const double ringCentre = 0.5;

  /// Ring stroke (cells) at the bottom and the top of the breath.
  static const double ringWidthMin = 0.09;
  static const double ringWidthMax = 0.15;

  /// Ring opacity at the bottom and the top of the breath.
  static const double ringAlphaMin = 0.6;
  static const double ringAlphaMax = 1.0;

  /// The glow is a stroke over the whole border strip, added to what is
  /// there (`BlendMode.plus`), so a colour only gets lighter, never muddy.
  static const double glowWidth = 0.9;
  static const double glowAlphaMax = 0.30;

  /// How much a yard that is not on turn is washed out. None: it keeps its
  /// full colour, so the board does not flicker each turn.
  static const double inactiveWash = 0;

  /// Breathing phase `0..1` (0 at the bottom): a smooth sine.
  static double breath(double tMs) =>
      0.5 - 0.5 * math.cos(2 * math.pi * tMs / periodMs);

  /// The look of a yard that is [live] (`0..1`, from `DockLook.live`: the
  /// handoff fades the focus out of one yard and into the next).
  static TurnFocusSample sample(
    double tMs,
    double live,
    MotionSpec spec,
  ) {
    final l = clamp01(live);
    if (l <= 0) {
      return TurnFocusSample.none;
    }
    // Reduced motion: no breathing, a steady mid-strength focus.
    final b = spec.reducedMotion ? 0.5 : breath(tMs);
    return TurnFocusSample(
      ringAlpha: l * (ringAlphaMin + (ringAlphaMax - ringAlphaMin) * b),
      ringWidth: ringWidthMin + (ringWidthMax - ringWidthMin) * b,
      glowAlpha: l * glowAlphaMax * (0.55 + 0.45 * b),
    );
  }
}
