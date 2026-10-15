import 'package:flutter/painting.dart';

/// Display names of the four seats (clockwise from the top-left yard).
const List<String> seatNames = ['Red', 'Green', 'Yellow', 'Blue'];

/// Colours for the board, tokens and dice (light and dark variants).
class LudoPalette {
  const LudoPalette({
    required this.background,
    required this.board,
    required this.cell,
    required this.cellLine,
    required this.yardInner,
    required this.text,
    required this.seat,
  });

  final Color background;
  final Color board;
  final Color cell;
  final Color cellLine;
  final Color yardInner;
  final Color text;

  /// Base colour per seat.
  final List<Color> seat;

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
  );

  static const LudoPalette dark = LudoPalette(
    background: Color(0xFF121212),
    board: Color(0xFF1E1E22),
    cell: Color(0xFF2B2B31),
    cellLine: Color(0xFF3D3D45),
    yardInner: Color(0xFF2B2B31),
    text: Color(0xFFEDEDED),
    seat: _seats,
  );

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  Color seatLight(int s) => Color.lerp(seat[s], _white, 0.45)!;

  Color seatDark(int s) => Color.lerp(seat[s], _black, 0.35)!;
}
