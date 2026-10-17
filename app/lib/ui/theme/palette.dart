import 'package:flutter/painting.dart';

/// Display names of the four seats (clockwise from the top-left yard).
const List<String> seatNames = ['Red', 'Green', 'Yellow', 'Blue'];

/// Colours for the table, board, tokens and dice (light and dark variants).
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

  static const List<Color> _seats = [
    Color(0xFFE53935),
    Color(0xFF43A047),
    Color(0xFFFDD835),
    Color(0xFF1E88E5),
  ];

  static const LudoPalette light = LudoPalette(
    background: Color(0xFFF3F1EC),
    board: Color(0xFFFAF7F0),
    cell: Color(0xFFFFFFFF),
    cellLine: Color(0xFFCFC8BA),
    yardInner: Color(0xFFFFFFFF),
    text: Color(0xFF22201C),
    seat: _seats,
    // Warm linen.
    feltCentre: Color(0xFFE9E2D3),
    feltEdge: Color(0xFFCDC3AE),
    woodLight: Color(0xFFA06F42),
    woodDark: Color(0xFF6E4726),
    woodGrainDark: Color(0xFF3B2210),
    woodGrainLight: Color(0xFFC99562),
  );

  static const LudoPalette dark = LudoPalette(
    background: Color(0xFF121212),
    board: Color(0xFF1E1E22),
    cell: Color(0xFF2B2B31),
    cellLine: Color(0xFF3D3D45),
    yardInner: Color(0xFF2B2B31),
    text: Color(0xFFEDEDED),
    seat: _seats,
    // Dark neutral felt.
    feltCentre: Color(0xFF2A2D30),
    feltEdge: Color(0xFF111214),
    woodLight: Color(0xFF8C5E36),
    woodDark: Color(0xFF583820),
    woodGrainDark: Color(0xFF2E1A0B),
    woodGrainLight: Color(0xFFB0804F),
  );

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  Color seatLight(int s) => Color.lerp(seat[s], _white, 0.45)!;

  Color seatDark(int s) => Color.lerp(seat[s], _black, 0.35)!;
}
