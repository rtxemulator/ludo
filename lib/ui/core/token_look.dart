/// Look and reach numbers of the pawns (polish pass). Pure Dart, no Flutter.
library;

/// Sizes in grid units (1 = one cell); the painter only draws what is here.
class TokenLook {
  const TokenLook._();

  /// Pawn base-ring radius before the polish pass.
  static const double previousBaseRadius = 0.38;

  /// Pawn base-ring radius at scale 1: 18% bigger than before (15-20%).
  static const double baseRadius = 0.45;

  /// Contact shadow: tight dark core and a wider, softer penumbra, as
  /// multiples of the pawn radius.
  static const double shadowCoreScale = 1.0;
  static const double shadowPenumbraScale = 1.7;

  /// A stack of at least this many tokens shows a count badge.
  static const int badgeFrom = 3;
  static const double badgeRadius = 0.26;

  /// Badge centre, from the cell centre (symmetric corner, no "up").
  static const double badgeOffset = 0.36;

  /// Minimum tap target (dp, square side) of a token.
  static const double tapTargetDp = 48;

  /// The reach of a tap (cells, as a radius) so that a token's target is at
  /// least [tapTargetDp] wide for a board drawn with [cellPx] logical pixels
  /// per cell, never below the old 0.8 and never so wide that neighbouring
  /// tokens are indistinguishable.
  static double tapReach(double cellPx) {
    if (cellPx <= 0) {
      return 0.8;
    }
    return (tapTargetDp / 2 / cellPx).clamp(0.8, 1.4);
  }

  /// Whether a stack of [n] tokens gets a count badge.
  static bool showBadge(int n) => n >= badgeFrom;
}
