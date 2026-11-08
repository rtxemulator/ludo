import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';

import 'audio/audio_service.dart';
import 'audio/soloud_backend.dart';
import 'settings/game_settings.dart';
import 'settings/settings_store.dart';
import 'storage/save_flush_observer.dart';
import 'storage/sqflite_save_store.dart';
import 'ui/home/home_screen.dart';
import 'ui/home/saved_games_screen.dart';
import 'ui/replay/replay_screen.dart';
import 'ui/screens/game_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/setup/setup_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SettingsStore? settingsStore;
  try {
    settingsStore = await SettingsStore.open();
  } on Object {
    settingsStore = null; // defaults, nothing remembered
  }
  // The audio engine is not touched here: the app starts it after the first
  // frame (LudoApp), and any failure only turns the sound off.
  runApp(
    LudoApp(
      settingsStore: settingsStore,
      audio: AudioService(backend: SoloudBackend()),
    ),
  );
}

class LudoApp extends StatefulWidget {
  /// [library] and [settingsStore] are injectable for tests; the app opens
  /// the real ones when they are omitted (without a [settingsStore] nothing
  /// is remembered between launches).
  const LudoApp({super.key, this.library, this.settingsStore, this.audio});

  final SaveLibrary? library;
  final SettingsStore? settingsStore;

  /// App-wide sound (tests pass one on a fake backend, or none for silence).
  final AudioService? audio;

  @override
  State<LudoApp> createState() => _LudoAppState();
}

class _LudoAppState extends State<LudoApp> {
  // Both live as long as the app: the settings carry over from match to
  // match, and the setup screen reopens with the last table. Both are
  // restored from disk at launch and saved as they change.
  late final GameSettings _settings =
      widget.settingsStore?.loadSettings() ?? GameSettings();
  late MatchSetup _setup =
      widget.settingsStore?.loadSetup() ?? MatchSetup.hotSeat();

  // The database opens on first use, so building this costs nothing at launch.
  late final SaveLibrary _library =
      widget.library ?? SaveLibrary(SqfliteSaveStore());

  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  VoidCallback? _stopSavingSettings;
  VoidCallback? _unbindAudio;

  // The look the MaterialApp was built with: it is rebuilt only when one of
  // these changes (not on every volume tick).
  late ThemeMode _themeMode = _settings.themeMode;
  late PaletteId _paletteId = _settings.paletteId;

  @override
  void initState() {
    super.initState();
    _stopSavingSettings = widget.settingsStore?.bind(_settings);
    _settings.addListener(_onLook);
    final audio = widget.audio;
    if (audio != null) {
      _unbindAudio = audio.bind(_settings);
      // Lazy: after the first frame, never before runApp.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(audio.start());
      });
    }
  }

  void _onLook() {
    if (_themeMode != _settings.themeMode ||
        _paletteId != _settings.paletteId) {
      setState(() {
        _themeMode = _settings.themeMode;
        _paletteId = _settings.paletteId;
      });
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onLook);
    _unbindAudio?.call();
    unawaited(widget.audio?.dispose());
    _stopSavingSettings?.call();
    _settings.dispose();
    super.dispose();
  }

  void _remember(MatchSetup setup) {
    _setup = setup;
    unawaited(widget.settingsStore?.saveSetup(setup));
  }

  Route<void> _setupRoute() => MaterialPageRoute<void>(
        builder: (_) => SetupScreen(
          initial: _setup,
          onChanged: _remember,
          onPlay: _play,
          settings: _settings,
        ),
      );

  Future<void> _openSetup() async {
    await _navigator.currentState?.push(_setupRoute());
  }

  void _play(BuildContext context, MatchSetup setup) {
    _remember(setup);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          setup: setup,
          settings: _settings,
          audio: widget.audio,
          saves: _library.queue,
          onReplay: _replayGameJustPlayed,
        ),
      ),
    );
  }

  Future<void> _resume(GameSave save) async {
    _remember(save.setup);
    await _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          resumeFrom: save,
          settings: _settings,
          audio: widget.audio,
          saves: _library.queue,
          onReplay: _replayGameJustPlayed,
          // "Players & rules" in a resumed game opens the setup in its place.
          onSetup: () => unawaited(
            _navigator.currentState?.pushReplacement(_setupRoute()),
          ),
        ),
      ),
    );
  }

  /// Watches [opening]; the replay never writes anything.
  Future<void> _replay(ReplayOpening opening) async {
    final script = opening.script;
    if (script == null) {
      return;
    }
    await _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => ReplayScreen(
          script: script,
          salvaged: opening.salvaged,
          settings: _settings,
          audio: widget.audio,
        ),
      ),
    );
  }

  /// "Watch replay" at game over: the save is the one in memory (the game
  /// is over, so nothing is being written to it any more).
  void _replayGameJustPlayed(GameSave save) {
    unawaited(_replay(ReplayOpening.of(save)));
  }

  Future<void> _openSaved() async {
    await _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SavedGamesScreen(
          library: _library,
          onOpen: _resume,
          onReplay: _replay,
          // The empty list offers a new game in its own place.
          onNewGame: () => unawaited(
            _navigator.currentState?.pushReplacement(_setupRoute()),
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: _settings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SaveFlushObserver(
      queue: _library.queue,
      child: MaterialApp(
        title: 'Ludo',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigator,
        theme: ludoTheme(_paletteId, Brightness.light),
        darkTheme: ludoTheme(_paletteId, Brightness.dark),
        themeMode: _themeMode,
        home: HomeScreen(
          library: _library,
          onPlay: _openSetup,
          onContinue: _resume,
          onSavedGames: _openSaved,
          onSettings: _openSettings,
        ),
      ),
    );
  }
}
