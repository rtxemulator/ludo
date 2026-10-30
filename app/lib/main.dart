import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';

import 'settings/game_settings.dart';
import 'settings/settings_store.dart';
import 'storage/save_flush_observer.dart';
import 'storage/sqflite_save_store.dart';
import 'ui/home/home_screen.dart';
import 'ui/home/saved_games_screen.dart';
import 'ui/screens/game_screen.dart';
import 'ui/setup/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SettingsStore? settingsStore;
  try {
    settingsStore = await SettingsStore.open();
  } on Object {
    settingsStore = null; // defaults, nothing remembered
  }
  runApp(LudoApp(settingsStore: settingsStore));
}

class LudoApp extends StatefulWidget {
  /// [library] and [settingsStore] are injectable for tests; the app opens
  /// the real ones when they are omitted (without a [settingsStore] nothing
  /// is remembered between launches).
  const LudoApp({super.key, this.library, this.settingsStore});

  final SaveLibrary? library;
  final SettingsStore? settingsStore;

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

  @override
  void initState() {
    super.initState();
    _stopSavingSettings = widget.settingsStore?.bind(_settings);
  }

  @override
  void dispose() {
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
          saves: _library.queue,
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
          saves: _library.queue,
          // "Players & rules" in a resumed game opens the setup in its place.
          onSetup: () => unawaited(
            _navigator.currentState?.pushReplacement(_setupRoute()),
          ),
        ),
      ),
    );
  }

  Future<void> _openSaved() async {
    await _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SavedGamesScreen(library: _library, onOpen: _resume),
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
        theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
        darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: HomeScreen(
          library: _library,
          onPlay: _openSetup,
          onContinue: _resume,
          onSavedGames: _openSaved,
        ),
      ),
    );
  }
}
