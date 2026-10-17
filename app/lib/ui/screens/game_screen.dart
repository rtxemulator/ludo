import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ludo/ui/core/motion_spec.dart';

import '../../game/game_controller.dart';
import '../table/table_view.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';

/// Hot-seat game screen (Milestone 2): just the table. There is no status
/// text; the board and the docks are the HUD.
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
      // The table handles the system insets itself so the felt runs edge to
      // edge.
      body: AnimatedBuilder(
        animation: _game,
        builder: (context, _) => TableView(
          game: _game,
          palette: palette,
          shaders: _shaders!,
        ),
      ),
    );
  }
}
