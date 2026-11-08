import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ludo/ui/core/sfx.dart' show clampVolume;

import '../../settings/game_settings.dart';
import '../theme/palette.dart';

/// The settings rows, shared by the Home screen (`SettingsScreen`) and the
/// in-game menu. They are bound to one [GameSettings] and rebuild when it
/// changes. Rows are added here (sound, look), so both entry points get them.
/// The Look section sits after Sound and before the profiling overlay, so the
/// rows above it keep their places.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.settings});

  final GameSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final s = settings;
        final tableMode = s.orientation == UiOrientation.table;
        return ListView(
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            SwitchListTile(
              title: const Text('Haptics'),
              value: s.haptics,
              onChanged: (v) => s.haptics = v,
            ),
            ListTile(
              title: const Text('Reduce motion'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SegmentedButton<ReduceMotion>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ReduceMotion.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(value: ReduceMotion.on, label: Text('On')),
                    ButtonSegment(value: ReduceMotion.off, label: Text('Off')),
                  ],
                  selected: {s.reduceMotion},
                  onSelectionChanged: (v) => s.reduceMotion = v.first,
                ),
              ),
            ),
            ListTile(
              title: const Text('UI orientation'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SegmentedButton<UiOrientation>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: UiOrientation.table,
                      label: Text('Table'),
                    ),
                    ButtonSegment(
                      value: UiOrientation.fixed,
                      label: Text('Fixed'),
                    ),
                  ],
                  selected: {s.orientation},
                  onSelectionChanged: (v) => s.orientation = v.first,
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('Auto-rotate menu to active seat'),
              subtitle: tableMode ? null : const Text('Table orientation only'),
              value: s.autoRotateShared,
              onChanged: tableMode ? (v) => s.autoRotateShared = v : null,
            ),
            const _SectionHeader('Sound'),
            SwitchListTile(
              key: const ValueKey('sfx-switch'),
              title: const Text('Sound effects'),
              value: s.sfxEnabled,
              onChanged: (v) => s.sfxEnabled = v,
            ),
            _VolumeSlider(
              sliderKey: const ValueKey('sfx-volume'),
              label: 'Sound effects volume',
              value: s.sfxVolume,
              onChanged: s.sfxEnabled ? (v) => s.sfxVolume = v : null,
            ),
            SwitchListTile(
              key: const ValueKey('music-switch'),
              title: const Text('Music'),
              subtitle: const Text('Plays at the table and in replays'),
              value: s.musicEnabled,
              onChanged: (v) => s.musicEnabled = v,
            ),
            _VolumeSlider(
              sliderKey: const ValueKey('music-volume'),
              label: 'Music volume',
              value: s.musicVolume,
              onChanged: s.musicEnabled ? (v) => s.musicVolume = v : null,
            ),
            const _SectionHeader('Look'),
            ListTile(
              title: const Text('Theme'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SegmentedButton<ThemeMode>(
                  key: const ValueKey('theme-mode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                    ),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => s.themeMode = v.first,
                ),
              ),
            ),
            ListTile(
              title: const Text('Palette'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    for (final id in PaletteId.values) ...[
                      if (id != PaletteId.values.first)
                        const SizedBox(width: 8),
                      Expanded(
                        child: _PaletteTile(
                          id: id,
                          selected: s.paletteId == id,
                          onTap: () => s.paletteId = id,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('Frame timing overlay'),
              subtitle: const Text('fps, dropped frames, paint time'),
              value: s.frameOverlay,
              onChanged: (v) => s.frameOverlay = v,
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// A `0..1` slider with a spoken percentage; greyed out when [onChanged] is
/// null (its switch is off).
class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Slider(
        key: sliderKey,
        value: clampVolume(value),
        onChanged: onChanged,
        semanticFormatterCallback: (v) => '$label ${(v * 100).round()} percent',
      ),
    );
  }
}

/// Display name of a palette.
String paletteName(PaletteId id) => switch (id) {
      PaletteId.classic => 'Classic',
      PaletteId.slate => 'Slate',
      PaletteId.highContrast => 'High Contrast',
    };

/// One choice of the Palette row: a small drawing of the board with the four
/// seat colours, in the palette's own colours for the current brightness, and
/// its name. The selected one has a thick outline.
class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final PaletteId id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = LudoPalette.of(id, theme.brightness);
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      selected: selected,
      label: '${paletteName(id)} palette',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: ValueKey('palette-${id.name}'),
        borderRadius: radius,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(painter: PaletteSwatchPainter(palette)),
              ),
              const SizedBox(height: 6),
              Text(
                paletteName(id),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tiny Ludo board in [palette]: the board colour with the cross of cells
/// and the four yards in the seat colours (Red top left, then clockwise).
class PaletteSwatchPainter extends CustomPainter {
  PaletteSwatchPainter(this.palette);

  final LudoPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final unit = side / 15;
    final board = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, side, side),
      Radius.circular(unit * 1.2),
    );
    final fill = Paint();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, unit * 0.18)
      ..color = palette.cellLine;
    canvas.save();
    canvas.clipRRect(board);
    canvas.drawRRect(board, fill..color = palette.board);

    // The cross of cells.
    final arms = [
      Rect.fromLTWH(6 * unit, 0, 3 * unit, side),
      Rect.fromLTWH(0, 6 * unit, side, 3 * unit),
    ];
    for (final arm in arms) {
      canvas.drawRect(arm, fill..color = palette.cell);
    }

    // Yards: Red top left, Green top right, Yellow bottom right, Blue bottom
    // left, as on the table.
    const corners = [
      Offset(0, 0),
      Offset(9, 0),
      Offset(9, 9),
      Offset(0, 9),
    ];
    for (var s = 0; s < 4; s++) {
      final yard = Rect.fromLTWH(
        corners[s].dx * unit,
        corners[s].dy * unit,
        6 * unit,
        6 * unit,
      );
      canvas.drawRect(yard, fill..color = palette.seat[s]);
      canvas.drawRect(
        yard.deflate(unit * 1.2),
        fill..color = palette.yardInner,
      );
      canvas.drawCircle(
        yard.center,
        unit * 1.1,
        fill..color = palette.seat[s],
      );
    }
    // The outline of the cross, over the yards.
    for (final arm in arms) {
      canvas.drawRect(arm, line);
    }
    canvas.restore();
    canvas.drawRRect(board, line);
  }

  @override
  bool shouldRepaint(PaletteSwatchPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
