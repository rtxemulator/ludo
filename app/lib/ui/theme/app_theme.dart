import 'package:flutter/material.dart';
import 'package:ludo/ui/core/palette_spec.dart';

/// The Material theme of [id] for [brightness]: `ColorScheme.fromSeed` with
/// the palette's seed (High Contrast also raises the scheme's contrast).
/// Themes are built once and reused, so the app can ask for them on every
/// rebuild without making the whole tree think its theme changed.
ThemeData ludoTheme(PaletteId id, Brightness brightness) =>
    _themes[id.index * 2 + (brightness == Brightness.dark ? 1 : 0)];

final List<ThemeData> _themes = [
  for (final id in PaletteId.values)
    for (final dark in [false, true])
      ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(PaletteSpec.seedOf(id)),
          brightness: dark ? Brightness.dark : Brightness.light,
          contrastLevel: PaletteSpec.contrastLevelOf(id),
        ),
      ),
];
