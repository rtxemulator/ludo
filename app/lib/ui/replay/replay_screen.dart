import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ludo/storage/storage.dart';

import '../../game/replay_controller.dart';
import '../../settings/game_settings.dart';
import '../table/table_view.dart';
import '../theme/palette.dart';
import '../theme/token_shaders.dart';
import 'replay_controls.dart';

/// Watches a finished or in-progress game again, move by move.
///
/// The table is the same one the game uses, driven by a [ReplayController]:
/// nobody can roll or tap, no computer player thinks, and nothing is saved.
/// The table orientation, reduce-motion and haptics settings apply as in a
/// game. Leaving the screen stops the ticker and frees the table.
class ReplayScreen extends StatefulWidget {
  /// [controller] and [settings] are injectable for tests; when omitted the
  /// screen builds its own from [script].
  const ReplayScreen({
    super.key,
    required this.script,
    this.salvaged = false,
    this.controller,
    this.settings,
  });

  final ReplayScript script;

  /// The file was damaged and [script] is only its readable start.
  final bool salvaged;

  final ReplayController? controller;
  final GameSettings? settings;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen>
    with SingleTickerProviderStateMixin {
  late final ReplayController _replay =
      widget.controller ?? ReplayController(script: widget.script);
  late final GameSettings _settings = widget.settings ?? GameSettings();
  bool _systemReduced = false;
  late final Ticker _ticker;
  Brightness? _shaderBrightness;
  TokenShaders? _shaders;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _replay.tick());
    _replay.game.feedback.enabled = _settings.haptics;
    _replay.addListener(_syncTicker);
    _replay.game.addListener(_syncTicker);
    _settings.addListener(_onSettings);
    _syncTicker();
  }

  void _onSettings() {
    _replay.game.feedback.enabled = _settings.haptics;
    _replay.game.spec = _settings.motionSpec(systemReduced: _systemReduced);
    _syncTicker();
  }

  void _syncTicker() {
    if (_replay.needsTicker) {
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
    _replay.game.spec = _settings.motionSpec(systemReduced: _systemReduced);
  }

  @override
  void dispose() {
    _replay.removeListener(_syncTicker);
    _replay.game.removeListener(_syncTicker);
    _settings.removeListener(_onSettings);
    _ticker.dispose();
    if (widget.settings == null) {
      _settings.dispose();
    }
    if (widget.controller == null) {
      _replay.dispose();
    }
    super.dispose();
  }

  String? get _notice {
    final script = widget.script;
    if (widget.salvaged) {
      return 'Damaged save: replaying the first ${script.length} moves.';
    }
    if (script.partial) {
      return 'This replay stops after move ${script.length}: '
          'the next one is not valid.';
    }
    return null;
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
      body: Column(
        children: [
          Expanded(
            // The controls take the bottom inset; the table keeps the rest.
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: AnimatedBuilder(
                animation: Listenable.merge([_replay, _replay.game, _settings]),
                builder: (context, _) => TableView(
                  game: _replay.game,
                  settings: _settings,
                  palette: palette,
                  shaders: _shaders!,
                  onClose: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
          ReplayControls(replay: _replay, notice: _notice),
        ],
      ),
    );
  }
}
