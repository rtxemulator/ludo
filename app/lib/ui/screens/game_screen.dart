import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ludo/ui/core/motion_spec.dart';

import '../../game/game_controller.dart';
import '../dev/haptics_test_sheet.dart';
import '../dice/dice_view.dart';
import '../theme/palette.dart';
import '../table/table_view.dart';
import '../theme/token_shaders.dart';

/// Hot-seat game screen (Milestone 2): board, status line and dice.
class GameScreen extends StatefulWidget {
  /// [controller] is injectable for tests; when omitted the screen owns one.
  const GameScreen({super.key, this.controller});

  final GameController? controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController _game = widget.controller ?? GameController();
  late final Ticker _ticker;
  Brightness? _shaderBrightness;
  TokenShaders? _shaders;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _game.tick());
    _game.addListener(_syncTicker);
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
    _game.spec = MediaQuery.disableAnimationsOf(context)
        ? MotionSpec.reduced
        : MotionSpec.standard;
  }

  @override
  void dispose() {
    _game.removeListener(_syncTicker);
    _ticker.dispose();
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
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _game,
          builder: (context, _) => Column(
            children: [
              _TopBar(game: _game, palette: palette),
              Expanded(
                child: TableView(
                  game: _game,
                  palette: palette,
                  shaders: _shaders!,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DiceView(game: _game, palette: palette),
                    SizedBox(
                      height: 24,
                      child: Text(
                        _game.message ?? '',
                        style: TextStyle(color: palette.text),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.game, required this.palette});

  final GameController game;
  final LudoPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              game.statusText,
              style: TextStyle(
                color: palette.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Haptics test',
            icon: Icon(Icons.vibration, color: palette.text),
            onPressed: () => showHapticsTestSheet(context, game.feedback),
          ),
          IconButton(
            tooltip: 'New game',
            icon: Icon(Icons.refresh, color: palette.text),
            onPressed: game.newGame,
          ),
        ],
      ),
    );
  }
}
