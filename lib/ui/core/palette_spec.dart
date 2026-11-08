/// The look of the table and the screens (docs/ludo-sound-themes.md section
/// 6). The stored value is the enum name.
enum PaletteId { classic, slate, highContrast }

/// The colour values of one palette variant as packed `0xAARRGGBB` ints.
///
/// This is the single source of the hex values: the Flutter `LudoPalette`
/// (app) is built from it, and the contrast tests (pure Dart) read it.
class PaletteSpec {
  const PaletteSpec({
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

  final int background;
  final int board;
  final int cell;
  final int cellLine;
  final int yardInner;
  final int text;

  /// Red, Green, Yellow, Blue.
  final List<int> seat;
  final int feltCentre;
  final int feltEdge;
  final int woodLight;
  final int woodDark;
  final int woodGrainDark;
  final int woodGrainLight;

  /// The variant of [id] for a light or dark surface.
  static PaletteSpec of(PaletteId id, {required bool dark}) => switch (id) {
        PaletteId.classic => dark ? classicDark : classicLight,
        PaletteId.slate => dark ? slateDark : slateLight,
        PaletteId.highContrast => dark ? highContrastDark : highContrastLight,
      };

  /// Material `ColorScheme.fromSeed` seed of each palette.
  static int seedOf(PaletteId id) => switch (id) {
        PaletteId.classic => 0xFF6750A4, // Material 3 baseline
        PaletteId.slate => 0xFF546E7A, // blue grey
        PaletteId.highContrast => 0xFF0072B2, // Okabe-Ito blue
      };

  /// `ColorScheme.fromSeed(contrastLevel:)` of each palette (`1` = highest).
  static double contrastLevelOf(PaletteId id) =>
      id == PaletteId.highContrast ? 1.0 : 0.0;

  // ---- Classic (the look before Milestone 6) -------------------------------

  static const List<int> _classicSeats = [
    0xFFE53935,
    0xFF43A047,
    0xFFFDD835,
    0xFF1E88E5,
  ];

  static const PaletteSpec classicLight = PaletteSpec(
    background: 0xFFF3F1EC,
    board: 0xFFFAF7F0,
    cell: 0xFFFFFFFF,
    cellLine: 0xFFCFC8BA,
    yardInner: 0xFFFFFFFF,
    text: 0xFF22201C,
    seat: _classicSeats,
    feltCentre: 0xFFE9E2D3,
    feltEdge: 0xFFCDC3AE,
    woodLight: 0xFFA06F42,
    woodDark: 0xFF6E4726,
    woodGrainDark: 0xFF3B2210,
    woodGrainLight: 0xFFC99562,
  );

  static const PaletteSpec classicDark = PaletteSpec(
    background: 0xFF121212,
    board: 0xFF1E1E22,
    cell: 0xFF2B2B31,
    cellLine: 0xFF3D3D45,
    yardInner: 0xFF2B2B31,
    text: 0xFFEDEDED,
    seat: _classicSeats,
    feltCentre: 0xFF2A2D30,
    feltEdge: 0xFF111214,
    woodLight: 0xFF8C5E36,
    woodDark: 0xFF583820,
    woodGrainDark: 0xFF2E1A0B,
    woodGrainLight: 0xFFB0804F,
  );

  // ---- Slate: cool, quiet, darker frame, slightly desaturated seats --------

  static const PaletteSpec slateLight = PaletteSpec(
    background: 0xFFE4E9EF,
    board: 0xFFEEF2F6,
    cell: 0xFFFAFBFD,
    cellLine: 0xFFB4BECB,
    yardInner: 0xFFFAFBFD,
    text: 0xFF1D2530,
    seat: [0xFFC9524E, 0xFF4E9A5B, 0xFFDDBF4A, 0xFF4A86C2],
    feltCentre: 0xFFB9C5D3,
    feltEdge: 0xFF93A2B5,
    woodLight: 0xFF5E5047,
    woodDark: 0xFF3C322C,
    woodGrainDark: 0xFF211A15,
    woodGrainLight: 0xFF8A7767,
  );

  static const PaletteSpec slateDark = PaletteSpec(
    background: 0xFF0E1217,
    board: 0xFF1A212A,
    cell: 0xFF242D38,
    cellLine: 0xFF3A4757,
    yardInner: 0xFF242D38,
    text: 0xFFE4EAF1,
    seat: [0xFFD1625D, 0xFF5BA867, 0xFFE3C752, 0xFF5A93CF],
    feltCentre: 0xFF2A3644,
    feltEdge: 0xFF10151B,
    woodLight: 0xFF4A3E36,
    woodDark: 0xFF2E2621,
    woodGrainDark: 0xFF17120E,
    woodGrainLight: 0xFF6F5E50,
  );

  // ---- High Contrast: Okabe-Ito seats, black or white lines ----------------
  // Seats keep their hue family (vermillion red, bluish green, yellow, blue).

  static const PaletteSpec highContrastLight = PaletteSpec(
    background: 0xFFFFFFFF,
    board: 0xFFEDEDED,
    cell: 0xFFFFFFFF,
    cellLine: 0xFF111118,
    yardInner: 0xFFFFFFFF,
    text: 0xFF000000,
    seat: [0xFFD55E00, 0xFF009E73, 0xFFB38F00, 0xFF0072B2],
    feltCentre: 0xFFF2F0E6,
    feltEdge: 0xFFD9D5C4,
    woodLight: 0xFF6B4423,
    woodDark: 0xFF3A2210,
    woodGrainDark: 0xFF1E0F05,
    woodGrainLight: 0xFF9A6A3E,
  );

  static const PaletteSpec highContrastDark = PaletteSpec(
    background: 0xFF000000,
    board: 0xFF0A0A0A,
    cell: 0xFF2A2A2A,
    cellLine: 0xFFF5F3EA,
    yardInner: 0xFF2A2A2A,
    text: 0xFFFFFFFF,
    seat: [0xFFFF6B2B, 0xFF00C08B, 0xFFF0E442, 0xFF4DA3E0],
    feltCentre: 0xFF1A1A1A,
    feltEdge: 0xFF000000,
    woodLight: 0xFF8C5E36,
    woodDark: 0xFF583820,
    woodGrainDark: 0xFF2E1A0B,
    woodGrainLight: 0xFFB0804F,
  );
}
