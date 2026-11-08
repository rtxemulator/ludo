import 'dart:math' as math;

/// WCAG 2.x contrast maths on packed `0xAARRGGBB` colours (alpha ignored).
/// Pure Dart, so the palette tests run with plain `dart test`.

/// Relative luminance of [argb], `0` (black) to `1` (white).
double relativeLuminance(int argb) {
  double channel(int shift) {
    final c = ((argb >> shift) & 0xFF) / 255.0;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}

/// Contrast ratio of two colours, `1` (identical) to `21` (black on white).
double contrastRatio(int a, int b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
