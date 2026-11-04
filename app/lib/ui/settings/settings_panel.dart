import 'package:flutter/material.dart';
import 'package:ludo/ui/core/sfx.dart' show clampVolume;

import '../../settings/game_settings.dart';

/// The settings rows, shared by the Home screen (`SettingsScreen`) and the
/// in-game menu. They are bound to one [GameSettings] and rebuild when it
/// changes. Rows are added here (sound now, look later), so both entry
/// points get them.
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
