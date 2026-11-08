import 'package:ludo/ui/core/contrast.dart';
import 'package:ludo/ui/core/palette_spec.dart';
import 'package:test/test.dart';

/// Hue in degrees `0..360` of a packed colour.
double _hue(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255;
  final g = ((argb >> 8) & 0xFF) / 255;
  final b = (argb & 0xFF) / 255;
  final hi = [r, g, b].reduce((a, c) => a > c ? a : c);
  final lo = [r, g, b].reduce((a, c) => a < c ? a : c);
  final d = hi - lo;
  if (d == 0) {
    return 0;
  }
  double h;
  if (hi == r) {
    h = ((g - b) / d) % 6;
  } else if (hi == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  final deg = h * 60;
  return deg < 0 ? deg + 360 : deg;
}

String _r(double v) => v.toStringAsFixed(2);

void main() {
  const seatNames = ['Red', 'Green', 'Yellow', 'Blue'];
  final variants = <String, PaletteSpec>{
    for (final id in PaletteId.values)
      for (final dark in [false, true])
        '${id.name}/${dark ? 'dark' : 'light'}': PaletteSpec.of(id, dark: dark),
  };

  test('contrast maths: black on white is 21, equal colours are 1', () {
    expect(contrastRatio(0xFF000000, 0xFFFFFFFF), closeTo(21, 1e-9));
    expect(contrastRatio(0xFF123456, 0xFF123456), closeTo(1, 1e-9));
    expect(
      contrastRatio(0xFF777777, 0xFFFFFFFF),
      closeTo(4.48, 0.01),
    ); // the well-known #777 on white
  });

  test('report: contrast numbers of every palette', () {
    final out = StringBuffer('\nPalette contrast (WCAG ratios)\n');
    variants.forEach((name, p) {
      out.writeln(
        '$name: text/background ${_r(contrastRatio(p.text, p.background))}, '
        'text/board ${_r(contrastRatio(p.text, p.board))}, '
        'text/feltEdge ${_r(contrastRatio(p.text, p.feltEdge))}, '
        'line/board ${_r(contrastRatio(p.cellLine, p.board))}, '
        'line/cell ${_r(contrastRatio(p.cellLine, p.cell))}, '
        'seat/cell '
        '${[
          for (var s = 0; s < 4; s++)
            '${seatNames[s][0]} ${_r(contrastRatio(p.seat[s], p.cell))}'
        ].join(', ')}',
      );
    });
    // ignore: avoid_print
    print(out);
  });

  group('text is readable in every palette (4.5:1)', () {
    variants.forEach((name, p) {
      test(name, () {
        expect(contrastRatio(p.text, p.background), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(p.text, p.board), greaterThanOrEqualTo(4.5));
      });
    });
  });

  group('High Contrast (3:1 for lines and seats)', () {
    for (final dark in [false, true]) {
      final name = 'highContrast/${dark ? 'dark' : 'light'}';
      final p = PaletteSpec.of(PaletteId.highContrast, dark: dark);

      test('$name: cell lines against the board and the cells', () {
        expect(contrastRatio(p.cellLine, p.board), greaterThanOrEqualTo(3));
        expect(contrastRatio(p.cellLine, p.cell), greaterThanOrEqualTo(3));
      });

      for (var s = 0; s < 4; s++) {
        test('$name: ${seatNames[s]} against the cell', () {
          expect(contrastRatio(p.seat[s], p.cell), greaterThanOrEqualTo(3));
        });
      }

      test('$name: text on the felt (menu button) is 4.5:1', () {
        expect(contrastRatio(p.text, p.feltCentre), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(p.text, p.feltEdge), greaterThanOrEqualTo(4.5));
      });

      test('$name: seats keep their hue family', () {
        final hues = [for (final c in p.seat) _hue(c)];
        // Red / vermillion, green, yellow, blue.
        expect(hues[0], inInclusiveRange(0, 30));
        expect(hues[1], inInclusiveRange(140, 175));
        expect(hues[2], inInclusiveRange(40, 65));
        expect(hues[3], inInclusiveRange(195, 225));
      });
    }
  });

  group('every palette', () {
    variants.forEach((name, p) {
      test('$name: four distinct seat colours, opaque values', () {
        expect(p.seat.length, 4);
        expect(p.seat.toSet().length, 4);
        for (final c in [
          ...p.seat,
          p.background,
          p.board,
          p.cell,
          p.cellLine,
          p.yardInner,
          p.text,
          p.feltCentre,
          p.feltEdge,
          p.woodLight,
          p.woodDark,
          p.woodGrainDark,
          p.woodGrainLight,
        ]) {
          expect(c >> 24, 0xFF, reason: '$name 0x${c.toRadixString(16)}');
        }
      });
    });

    test('every palette has a seed and only High Contrast raises contrast', () {
      for (final id in PaletteId.values) {
        expect(PaletteSpec.seedOf(id) >> 24, 0xFF);
        expect(
          PaletteSpec.contrastLevelOf(id),
          id == PaletteId.highContrast ? 1.0 : 0.0,
        );
      }
      expect(
        {for (final id in PaletteId.values) PaletteSpec.seedOf(id)}.length,
        PaletteId.values.length,
      );
    });

    test('Classic keeps the colours of the look before Milestone 6', () {
      const light = PaletteSpec.classicLight;
      expect(light.background, 0xFFF3F1EC);
      expect(light.seat, [0xFFE53935, 0xFF43A047, 0xFFFDD835, 0xFF1E88E5]);
      expect(PaletteSpec.classicDark.board, 0xFF1E1E22);
      expect(PaletteSpec.classicDark.seat, light.seat);
    });
  });
}
