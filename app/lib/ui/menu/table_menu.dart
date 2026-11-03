import 'package:flutter/material.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../../settings/game_settings.dart';
import '../settings/settings_panel.dart';
import 'turned_box.dart';

enum _Page { main, settings, rules }

/// Opens the menu sheet: New game, Settings, Rules (placeholder) and Close.
///
/// The card faces the seat on turn (UI/UX doc section 3): it turns with the
/// active seat when the orientation is `Table` and auto-rotate is on.
Future<void> showTableMenu(
  BuildContext context, {
  required GameController game,
  required GameSettings settings,
  required TableLayout layout,
  VoidCallback? onSetup,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => TableMenu(
      game: game,
      settings: settings,
      layout: layout,
      onSetup: onSetup,
    ),
  );
}

/// The turned menu card.
class TableMenu extends StatefulWidget {
  const TableMenu({
    super.key,
    required this.game,
    required this.settings,
    required this.layout,
    this.onSetup,
  });

  final GameController game;
  final GameSettings settings;
  final TableLayout layout;

  /// "Players & rules": back to the setup screen. `null` hides the entry.
  final VoidCallback? onSetup;

  @override
  State<TableMenu> createState() => _TableMenuState();
}

class _TableMenuState extends State<TableMenu> {
  _Page _page = _Page.main;

  GameController get _game => widget.game;
  GameSettings get _settings => widget.settings;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final side = (screen.shortestSide * 0.92).clamp(240.0, 380.0);
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([_game, _settings]),
        builder: (context, _) {
          final seat = _game.activeSeat ?? _game.winnerSeat ?? 0;
          final turns = sharedUiTurns(
            widget.layout,
            seat,
            _settings.orientation,
            autoRotate: _settings.autoRotateShared,
          );
          return TurnedBox(
            turns: turns,
            side: side,
            animate: !_game.spec.reducedMotion,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: switch (_page) {
                _Page.main => _main(context),
                _Page.settings => _settingsPage(context),
                _Page.rules => _rules(context),
              },
            ),
          );
        },
      ),
    );
  }

  Widget _main(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            'Ludo',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('New game'),
          onTap: () {
            Navigator.of(context).pop();
            _game.newGame();
          },
        ),
        if (widget.onSetup != null)
          ListTile(
            leading: const Icon(Icons.groups),
            title: const Text('Players & rules'),
            onTap: () {
              Navigator.of(context).pop();
              widget.onSetup!();
            },
          ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Settings'),
          onTap: () => setState(() => _page = _Page.settings),
        ),
        ListTile(
          leading: const Icon(Icons.menu_book),
          title: const Text('Rules'),
          onTap: () => setState(() => _page = _Page.rules),
        ),
        ListTile(
          leading: const Icon(Icons.close),
          title: const Text('Close'),
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _header(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _page = _Page.main),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _rules(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Rules'),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text('The rule presets and house rules will be listed here.'),
        ),
        SwitchListTile(
          title: const Text('Banked rolls'),
          subtitle: const Text(
            'Sixes stack: roll them all, then spend the whole bank. '
            'Changing this starts a new game.',
          ),
          value: _game.banked,
          onChanged: _game.setBankedRolls,
        ),
      ],
    );
  }

  Widget _settingsPage(BuildContext context) {
    return Column(
      children: [
        _header('Settings'),
        Expanded(child: SettingsPanel(settings: _settings)),
      ],
    );
  }
}
