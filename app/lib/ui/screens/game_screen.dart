import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../game/game_controller.dart';
import '../../settings/game_settings.dart';
import '../table/table_view.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';

/// Hot-seat game screen (Milestone 2): just the table. There is no status
/// text; the board and the docks are the HUD.
class GameScreen extends StatefulWidget {
  /// [controller] is injectable for tests; when omitted the screen owns one.
  const GameScreen({super.key, this.controller, this.settings});

  final GameController? controller;

  /// Injectable for tests; when omitted the screen owns one.
  final GameSettings? settings;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController _game = widget.controller ?? GameController();
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
        ),
      ),
    );
  }
}
