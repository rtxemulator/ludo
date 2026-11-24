import 'palette_spec.dart';
import 'pt.dart';
import 'seeded.dart';

/// The "atmosphere" of the table (polish pass 1, step 8): paper grain on the
/// board, a vignette on board and felt and a satin sheen on the wooden frame.
///
/// Everything here is a number or a deterministic point set: the painters
/// bake it once into their cached static layers (nothing runs per frame), and
/// every colour is taken from the active palette. The strength is `0` (off)
/// to `1` (full); the alphas below are scaled by it with [alpha].
abstract final class Atmosphere {
  /// Dots per set (dark and light) of paper grain over the 15 x 15 board.
  static const int boardGrainDots = 640;

  /// Diameter (cells) of one grain dot.
  static const double boardGrainSize = 0.03;

  /// Alpha (of 255) of the dark and the light grain at full strength.
  static const int boardGrainDarkAlpha = 0x16;
  static const int boardGrainLightAlpha = 0x1C;

  /// Radius (of the board's width) at which the board vignette is darkest,
  /// where it starts (`0..1` of that radius) and its darkest alpha.
  static const double boardVignetteRadius = 0.8;
  static const double boardVignetteStart = 0.5;
  static const int boardVignetteAlpha = 0x2E;

  /// The felt's vignette: where it starts (of the table's half diagonal) and
  /// its darkest alpha.
  static const double feltVignetteStart = 0.55;
  static const int feltVignetteAlpha = 0x3A;

  /// Wood sheen: the strength (alpha) of the main ridge of light along the
  /// middle of each frame side, its width as a part of the frame's width, how
  /// much it is lightened toward white and where along the side it fades in
  /// and out (parts of the side's length).
  static const int sheenAlpha = 0x40;
  static const double sheenWidth = 0.22;
  static const double sheenWhite = 0.5;
  static const List<double> sheenStops = [0.08, 0.3, 0.7, 0.92];

  /// How strongly [id] shows the atmosphere: High Contrast keeps the board
  /// clean so the seats stay unmistakable.
  static double strengthOf(PaletteId id) =>
      id == PaletteId.highContrast ? 0.35 : 1.0;

  /// [base] (of 255) scaled by [strength] and clamped to a valid alpha.
  static int alpha(int base, double strength) =>
      (base * strength).round().clamp(0, 255);

  /// [count] points of paper grain inside `[0, width) x [0, height)`: a
  /// jittered grid (one point per cell, so no clumps and no bare patches) of
  /// at least [count] cells, thinned evenly to exactly [count]. Deterministic
  /// for a [seed].
  static List<Pt> grainPoints({
    required int seed,
    required int count,
    required double width,
    required double height,
  }) {
    if (count <= 0 || width <= 0 || height <= 0) {
      return const [];
    }
    final rnd = Seeded(seed);
    var cols = (count * width / height).abs().isFinite
        ? _isqrt((count * width / height).ceil())
        : 1;
    cols = cols < 1 ? 1 : cols;
    final rows = (count / cols).ceil();
    final cw = width / cols;
    final ch = height / rows;
    final total = cols * rows;
    final points = <Pt>[];
    for (var k = 0; k < count; k++) {
      final index = (k * total) ~/ count;
      final col = index % cols;
      final row = index ~/ cols;
      points.add(
        Pt(
          (col + rnd.next()) * cw,
          (row + rnd.next()) * ch,
        ),
      );
    }
    return points;
  }

  /// Smallest `n` with `n * n >= x` (for `x >= 1`).
  static int _isqrt(int x) {
    var n = 1;
    while (n * n < x) {
      n++;
    }
    return n;
  }
}
