import 'package:flutter/material.dart';

import '../../settings/game_settings.dart';

/// The settings rows, shared by the Home screen (`SettingsScreen`) and the
/// in-game menu. They are bound to one [GameSettings] and rebuild when it
/// changes. Later milestones add their rows here (sound, look), so both
/// entry points get them.
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
