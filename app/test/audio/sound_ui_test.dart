import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludo_app/audio/audio_service.dart';
import 'package:ludo_app/game/game_controller.dart';
import 'package:ludo_app/game/replay_controller.dart';
import 'package:ludo_app/main.dart';
import 'package:ludo_app/settings/game_settings.dart';
import 'package:ludo_app/ui/replay/replay_screen.dart';
import 'package:ludo_app/ui/screens/game_screen.dart';
import 'package:ludo_app/ui/settings/settings_screen.dart';

import '../fakes/fake_audio.dart';
import '../save_fixtures.dart';

class _Audio {
  final backend = FakeAudioBackend();
  final clock = FakeAudioClock();
  late final AudioService service = AudioService(
    backend: backend,
    clock: clock,
    observeLifecycle: false,
  );
}

final _sfxSwitch = find.byKey(const ValueKey('sfx-switch'));
final _sfxSlider = find.byKey(const ValueKey('sfx-volume'));
final _musicSwitch = find.byKey(const ValueKey('music-switch'));
final _musicSlider = find.byKey(const ValueKey('music-volume'));

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('Sound rows', () {
    testWidgets('the panel has a Sound section with both switches and sliders',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: GameSettings())),
      );
      expect(find.text('Sound'), findsOneWidget);
      expect(find.text('Sound effects'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      expect(_sfxSwitch, findsOneWidget);
      expect(_sfxSlider, findsOneWidget);
      expect(_musicSwitch, findsOneWidget);
      expect(_musicSlider, findsOneWidget);
    });

    testWidgets('switches and sliders change the model', (tester) async {
      _phone(tester);
      final settings = GameSettings(musicVolume: 0.4);
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: settings)),
      );
      expect(settings.sfxEnabled, isTrue);
      expect(settings.musicEnabled, isFalse);

      await tester.tap(_musicSwitch);
      await tester.pump();
      expect(settings.musicEnabled, isTrue);

      final before = settings.musicVolume;
      await tester.drag(_musicSlider, const Offset(120, 0));
      await tester.pump();
      expect(settings.musicVolume, greaterThan(before));

      final sfxBefore = settings.sfxVolume;
      await tester.drag(_sfxSlider, const Offset(-120, 0));
      await tester.pump();
      expect(settings.sfxVolume, lessThan(sfxBefore));

      await tester.tap(_sfxSwitch);
      await tester.pump();
      expect(settings.sfxEnabled, isFalse);
    });

    testWidgets('a slider is greyed out while its switch is off',
        (tester) async {
      _phone(tester);
      final settings = GameSettings();
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: settings)),
      );
      Slider slider(Finder f) => tester.widget<Slider>(f);
      expect(slider(_sfxSlider).onChanged, isNotNull);
      expect(slider(_musicSlider).onChanged, isNull, reason: 'music is off');

      settings.musicEnabled = true;
      settings.sfxEnabled = false;
      await tester.pump();
      expect(slider(_musicSlider).onChanged, isNotNull);
      expect(slider(_sfxSlider).onChanged, isNull);
    });

    testWidgets('the rows show the model and follow it', (tester) async {
      _phone(tester);
      final settings = GameSettings(sfxVolume: 0.3, musicEnabled: true);
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: settings)),
      );
      expect(tester.widget<Slider>(_sfxSlider).value, closeTo(0.3, 1e-9));
      expect(tester.widget<SwitchListTile>(_musicSwitch).value, isTrue);
      settings.sfxVolume = 0.9;
      settings.musicEnabled = false;
      await tester.pump();
      expect(tester.widget<Slider>(_sfxSlider).value, closeTo(0.9, 1e-9));
      expect(tester.widget<SwitchListTile>(_musicSwitch).value, isFalse);
    });
  });

  group('in the app', () {
    testWidgets('the audio starts after the first frame, never before',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final audio = _Audio();
      expect(audio.backend.initCalls, 0);
      await tester.pumpWidget(
        LudoApp(
          library: SaveLibrary(InMemorySaveStore()),
          audio: audio.service,
        ),
      );
      await tester.pumpAndSettle();
      expect(audio.backend.initCalls, 1);
      expect(audio.service.ready, isTrue);
    });

    testWidgets('Home, Setup and Settings stay silent even with music on',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final audio = _Audio();
      await tester.pumpWidget(
        LudoApp(
          library: SaveLibrary(InMemorySaveStore()),
          audio: audio.service,
        ),
      );
      await tester.pumpAndSettle();

      // Settings: turn the music on there.
      await tester.tap(find.byKey(const ValueKey('home-settings')));
      await tester.pumpAndSettle();
      await tester.tap(_musicSwitch);
      await tester.pumpAndSettle();
      expect(audio.service.musicEnabled, isTrue, reason: 'applies live');
      expect(audio.backend.startMusicCalls, 0);

      await tester.tap(_sfxSwitch);
      await tester.pumpAndSettle();
      expect(audio.service.sfxEnabled, isFalse, reason: 'applies live');
      await tester.drag(_sfxSlider, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(audio.service.sfxVolume, lessThan(defaultSfxVolume));

      // Back on Home and on Setup: still silent.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-play')));
      await tester.pumpAndSettle();
      expect(audio.backend.startMusicCalls, 0);
      expect(audio.backend.musicPlaying, isFalse);
    });
  });

  group('music only on the table and the replay', () {
    testWidgets('the table plays it while it is up and fades it out after',
        (tester) async {
      _phone(tester);
      final audio = _Audio();
      await audio.service.start();
      final settings = GameSettings(haptics: false, musicEnabled: true);
      final game = GameController(seed: 3, haptics: false);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            controller: game,
            settings: settings,
            audio: audio.service,
          ),
        ),
      );
      expect(audio.backend.startMusicCalls, 1);
      audio.clock.advance(500);
      expect(audio.backend.musicPlaying, isTrue);

      await tester.pumpWidget(const SizedBox());
      audio.clock.advance(500);
      expect(audio.backend.musicPlaying, isFalse);
      game.dispose();
      settings.dispose();
    });

    testWidgets('the table is silent when the music setting is off',
        (tester) async {
      _phone(tester);
      final audio = _Audio();
      await audio.service.start();
      final settings = GameSettings(haptics: false);
      final game = GameController(seed: 3, haptics: false);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            controller: game,
            settings: settings,
            audio: audio.service,
          ),
        ),
      );
      audio.clock.advance(1000);
      expect(audio.backend.startMusicCalls, 0);

      settings.musicEnabled = true; // live, from the menu
      await tester.pump();
      expect(audio.backend.startMusicCalls, 1);
      await tester.pumpWidget(const SizedBox());
      game.dispose();
      settings.dispose();
    });

    testWidgets(
        'the replay plays it too, and keeps it when it closes over '
        'the table', (tester) async {
      _phone(tester);
      final audio = _Audio();
      await audio.service.start();
      final settings = GameSettings(haptics: false, musicEnabled: true);
      final game = GameController(seed: 3, haptics: false);
      final save = playSave(id: 'm', at: day, decisions: 10);
      final replay = ReplayController(
        script: ReplayScript.of(save),
        haptics: false,
        audio: audio.service,
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: GameScreen(
            controller: game,
            settings: settings,
            audio: audio.service,
          ),
        ),
      );
      audio.clock.advance(500);
      expect(audio.backend.startMusicCalls, 1);

      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ReplayScreen(
            script: replay.script,
            controller: replay,
            settings: settings,
            audio: audio.service,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      audio.clock.advance(1000);
      expect(audio.backend.musicPlaying, isTrue);
      expect(audio.backend.startMusicCalls, 1, reason: 'one continuous track');

      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      audio.clock.advance(1000);
      expect(audio.backend.musicPlaying, isTrue, reason: 'the table is back');

      await tester.pumpWidget(const SizedBox());
      audio.clock.advance(1000);
      expect(audio.backend.musicPlaying, isFalse);
      game.dispose();
      replay.dispose();
      settings.dispose();
    });

    testWidgets('a replay screen alone plays and then stops its music',
        (tester) async {
      _phone(tester);
      final audio = _Audio();
      await audio.service.start();
      final settings = GameSettings(haptics: false, musicEnabled: true);
      final save = playSave(id: 'r', at: day, decisions: 10);
      await tester.pumpWidget(
        MaterialApp(
          home: ReplayScreen(
            script: ReplayScript.of(save),
            settings: settings,
            audio: audio.service,
          ),
        ),
      );
      expect(audio.backend.startMusicCalls, 1);
      await tester.pumpWidget(const SizedBox());
      audio.clock.advance(1000);
      expect(audio.backend.musicPlaying, isFalse);
      settings.dispose();
    });
  });
}
