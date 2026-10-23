import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ludo/seats/seats.dart';

import 'settings/game_settings.dart';
import 'ui/screens/game_screen.dart';
import 'ui/setup/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const LudoApp());
}

class LudoApp extends StatefulWidget {
  const LudoApp({super.key});

  @override
  State<LudoApp> createState() => _LudoAppState();
}

class _LudoAppState extends State<LudoApp> {
  // Both live as long as the app: the settings carry over from match to
  // match, and the setup screen reopens with the last table. (Saved to disk
  // with the saves and settings milestones.)
  final GameSettings _settings = GameSettings();
  MatchSetup _setup = MatchSetup.hotSeat();

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  void _play(BuildContext context, MatchSetup setup) {
    _setup = setup;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(setup: setup, settings: _settings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: SetupScreen(
        initial: _setup,
        onChanged: (setup) => _setup = setup,
        onPlay: _play,
      ),
    );
  }
}
