import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';

import '../../game/game_controller.dart';
import '../../settings/game_settings.dart';
import '../table/table_view.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';

/// The game screen: just the table. There is no status text; the board and
/// the docks are the HUD. Seats come from [setup] (humans tap, AI seats play
/// by themselves).
class GameScreen extends StatefulWidget {
  /// [controller] is injectable for tests; when omitted the screen owns one,
  /// built for [setup] (four humans when that is omitted too).
  const GameScreen({
    super.key,
    this.controller,
    this.settings,
    this.setup,
    this.saves,
    this.resumeFrom,
    this.onSetup,
  });

  final GameController? controller;

  /// The seats and rules to play; ignored when a [controller] is given.
  final MatchSetup? setup;

  /// Injectable for tests; when omitted the screen owns one.
  final GameSettings? settings;

  /// Where the game autosaves; ignored when a [controller] is given. No
  /// saving when omitted.
  final SaveWriteQueue? saves;

  /// Continues this save instead of starting [setup]; ignored when a
  /// [controller] is given.
  final GameSave? resumeFrom;

  /// What "Players & rules" in the menu does. When omitted it goes back one
  /// screen (and is hidden when there is none).
  final VoidCallback? onSetup;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController _game = widget.controller ??
      GameController(
        setup: widget.setup,
        saves: widget.saves,
        resumeFrom: widget.resumeFrom,
      );
  late final GameSettings _settings =
      widget.settings ?? GameSettings(haptics: _game.feedback.enabled);
  bool _systemReduced = false;
  late final Ticker _ticker;
  Brightness? _shaderBrightness;
  TokenShaders? _shaders;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _game.tick());
    // Settings outlive a match (they belong to the app): apply them to this
    // one before the first frame.
    _game.feedback.enabled = _settings.haptics;
    _game.addListener(_syncTicker);
    _settings.addListener(_onSettings);
    _syncTicker();
  }

  /// Pushes the settings into the controller (haptics toggle, motion spec).
  void _onSettings() {
    _game.feedback.enabled = _settings.haptics;
    _game.spec = _settings.motionSpec(systemReduced: _systemReduced);
    _syncTicker();
  }

  void _syncTicker() {
    if (_game.needsTicker) {
      if (!_ticker.isActive) {
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _systemReduced = MediaQuery.disableAnimationsOf(context);
    _game.spec = _settings.motionSpec(systemReduced: _systemReduced);
  }

  @override
  void dispose() {
    _game.removeListener(_syncTicker);
    _settings.removeListener(_onSettings);
    _ticker.dispose();
    if (widget.settings == null) {
      _settings.dispose();
    }
    if (widget.controller == null) {
      _game.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette =
        brightness == Brightness.dark ? LudoPalette.dark : LudoPalette.light;
    if (_shaders == null || _shaderBrightness != brightness) {
      _shaders = TokenShaders(palette);
      _shaderBrightness = brightness;
    }
    return Scaffold(
      backgroundColor: palette.feltEdge,
      // The table handles the system insets itself so the felt runs edge to
      // edge.
      body: AnimatedBuilder(
        animation: Listenable.merge([_game, _settings]),
        builder: (context, _) => TableView(
          game: _game,
          settings: _settings,
          palette: palette,
          shaders: _shaders!,
          // Back to the setup screen, when this screen was opened from it.
          onSetup: widget.onSetup ??
              (Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : null),
        ),
      ),
    );
  }
}
