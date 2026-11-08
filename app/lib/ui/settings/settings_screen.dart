import 'package:flutter/material.dart';

import '../../settings/game_settings.dart';
import 'settings_panel.dart';

/// Settings as a screen of its own, opened from the gear button on Home. The
/// in-game menu shows the same [SettingsPanel] inside its card.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final GameSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SettingsPanel(settings: settings),
          ),
        ),
      ),
    );
  }
}
