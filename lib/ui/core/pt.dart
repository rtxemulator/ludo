import 'dart:math' as math;

/// Minimal 2D point in board grid units (1.0 = one board cell).
///
/// Deliberately not `dart:ui`'s `Offset`, so `lib/ui/core` stays testable
/// with plain `dart test`.
class Pt {
  const Pt(this.x, this.y);

  static const Pt zero = Pt(0, 0);

  final double x;
  final double y;

  Pt operator +(Pt other) => Pt(x + other.x, y + other.y);

  Pt operator -(Pt other) => Pt(x - other.x, y - other.y);

  Pt operator *(double k) => Pt(x * k, y * k);

  /// Euclidean distance to [other].
  double distanceTo(Pt other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Linear interpolation; [t] is not clamped.
  static Pt lerp(Pt a, Pt b, double t) =>
      Pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

  @override
  bool operator ==(Object other) => other is Pt && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Pt($x, $y)';
}
