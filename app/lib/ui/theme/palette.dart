import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:ludo/ui/core/palette_spec.dart';

export 'package:ludo/ui/core/palette_spec.dart' show PaletteId;

/// Display names of the four seats (clockwise from the top-left yard).
const List<String> seatNames = ['Red', 'Green', 'Yellow', 'Blue'];

/// Colours for the table, board, tokens and dice. There is one per palette
/// and brightness ([LudoPalette.of]); the hex values live in the pure-Dart
/// `PaletteSpec` (so the contrast tests can read them) and are listed in
/// docs/ludo-sound-themes.md section 6.
///
/// The instances are created once and shared, so a palette can be compared
/// with `==` (identity): the painters' `shouldRepaint` and the shader cache
/// rely on that.
class LudoPalette {
  const LudoPalette({
    required this.background,
    required this.board,
    required this.cell,
    required this.cellLine,
    required this.yardInner,
    required this.text,
    required this.seat,
    required this.feltCentre,
    required this.feltEdge,
    required this.woodLight,
    required this.woodDark,
    required this.woodGrainDark,
    required this.woodGrainLight,
  });

  factory LudoPalette.fromSpec(PaletteSpec s) => LudoPalette(
        background: Color(s.background),
        board: Color(s.board),
        cell: Color(s.cell),
        cellLine: Color(s.cellLine),
        yardInner: Color(s.yardInner),
        text: Color(s.text),
        seat: List<Color>.unmodifiable([for (final c in s.seat) Color(c)]),
        feltCentre: Color(s.feltCentre),
        feltEdge: Color(s.feltEdge),
        woodLight: Color(s.woodLight),
        woodDark: Color(s.woodDark),
        woodGrainDark: Color(s.woodGrainDark),
        woodGrainLight: Color(s.woodGrainLight),
      );

  final Color background;
  final Color board;
  final Color cell;
  final Color cellLine;
  final Color yardInner;
  final Color text;

  /// Base colour per seat.
  final List<Color> seat;

  /// Table felt: colour in the middle and at the screen edge (vignette).
  final Color feltCentre;
  final Color feltEdge;

  /// Wooden frame: base browns and the two grain tints.
  final Color woodLight;
  final Color woodDark;
  final Color woodGrainDark;
  final Color woodGrainLight;

  // Index: palette index * 2 (+ 1 for dark).
  static final List<LudoPalette> _all = [
    for (final id in PaletteId.values)
      for (final dark in [false, true])
        LudoPalette.fromSpec(PaletteSpec.of(id, dark: dark)),
  ];

  /// The palette [id] for a light or dark [brightness]. Always the same
  /// instance for the same arguments.
  static LudoPalette of(PaletteId id, Brightness brightness) =>
      _all[id.index * 2 + (brightness == Brightness.dark ? 1 : 0)];

  /// Classic, light.
  static final LudoPalette light = of(PaletteId.classic, Brightness.light);

  /// Classic, dark.
  static final LudoPalette dark = of(PaletteId.classic, Brightness.dark);

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  Color seatLight(int s) => Color.lerp(seat[s], _white, 0.45)!;

  Color seatDark(int s) => Color.lerp(seat[s], _black, 0.35)!;
}
