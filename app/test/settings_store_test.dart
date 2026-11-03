import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludo_app/settings/game_settings.dart';
import 'package:ludo_app/settings/settings_store.dart';

Future<SettingsStore> _open(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsStore.open();
}

void main() {
  test('a fresh install gets the defaults', () async {
    final store = await _open({});
    final settings = store.loadSettings();
    expect(settings.haptics, isTrue);
    expect(settings.reduceMotion, ReduceMotion.system);
    expect(settings.orientation, UiOrientation.table);
    expect(settings.autoRotateShared, isTrue);
    expect(settings.frameOverlay, isFalse);
    expect(settings.sfxEnabled, isTrue);
    expect(settings.sfxVolume, 0.8);
    expect(settings.musicEnabled, isFalse);
    expect(settings.musicVolume, 0.4);
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.paletteId, PaletteId.classic);
    expect(store.loadSetup(), MatchSetup.hotSeat());
  });

  test('settings round trip', () async {
    final store = await _open({});
    final settings = GameSettings(
      haptics: false,
      reduceMotion: ReduceMotion.on,
      orientation: UiOrientation.fixed,
      autoRotateShared: false,
      frameOverlay: true,
      sfxEnabled: false,
      sfxVolume: 0.25,
      musicEnabled: true,
      musicVolume: 0.9,
      themeMode: ThemeMode.dark,
      paletteId: PaletteId.highContrast,
    );
    await store.saveSettings(settings);

    final again = SettingsStore(await SharedPreferences.getInstance());
    final loaded = again.loadSettings();
    expect(loaded.haptics, isFalse);
    expect(loaded.reduceMotion, ReduceMotion.on);
    expect(loaded.orientation, UiOrientation.fixed);
    expect(loaded.autoRotateShared, isFalse);
    expect(loaded.frameOverlay, isTrue);
    expect(loaded.sfxEnabled, isFalse);
    expect(loaded.sfxVolume, 0.25);
    expect(loaded.musicEnabled, isTrue);
    expect(loaded.musicVolume, 0.9);
    expect(loaded.themeMode, ThemeMode.dark);
    expect(loaded.paletteId, PaletteId.highContrast);
  });

  test('every theme mode and palette round trips', () async {
    for (final mode in ThemeMode.values) {
      for (final id in PaletteId.values) {
        final store = await _open({});
        await store.saveSettings(GameSettings(themeMode: mode, paletteId: id));
        final loaded = store.loadSettings();
        expect(loaded.themeMode, mode);
        expect(loaded.paletteId, id);
      }
    }
  });

  test('a bound settings object is saved after every change', () async {
    final store = await _open({});
    final settings = store.loadSettings();
    final stop = store.bind(settings);
    settings.haptics = false;
    settings.reduceMotion = ReduceMotion.off;
    settings.sfxVolume = 0.3;
    settings.paletteId = PaletteId.slate;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final loaded = store.loadSettings();
    expect(loaded.haptics, isFalse);
    expect(loaded.reduceMotion, ReduceMotion.off);
    expect(loaded.sfxVolume, 0.3);
    expect(loaded.paletteId, PaletteId.slate);

    stop();
    settings.haptics = true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(store.loadSettings().haptics, isFalse);
  });

  test('missing, mistyped or unknown values fall back one by one', () async {
    final store = await _open({
      SettingsStore.hapticsKey: 'yes',
      SettingsStore.reduceMotionKey: 'sideways',
      SettingsStore.orientationKey: 7,
      SettingsStore.autoRotateKey: false,
    });
    final settings = store.loadSettings();
    expect(settings.haptics, isTrue);
    expect(settings.reduceMotion, ReduceMotion.system);
    expect(settings.orientation, UiOrientation.table);
    expect(settings.autoRotateShared, isFalse); // the good one is kept
    expect(settings.frameOverlay, isFalse);
  });

  test('bad sound and look values fall back one by one', () async {
    final cases = <String, Object>{
      SettingsStore.sfxEnabledKey: 'on',
      SettingsStore.sfxVolumeKey: 'loud',
      SettingsStore.musicEnabledKey: 1,
      SettingsStore.musicVolumeKey: true,
      SettingsStore.themeModeKey: 'sepia',
      SettingsStore.paletteIdKey: 42,
    };
    final store = await _open(cases);
    final settings = store.loadSettings();
    expect(settings.sfxEnabled, isTrue);
    expect(settings.sfxVolume, 0.8);
    expect(settings.musicEnabled, isFalse);
    expect(settings.musicVolume, 0.4);
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.paletteId, PaletteId.classic);

    // One bad value does not spoil its neighbours.
    final mixed = await _open({
      SettingsStore.sfxVolumeKey: 0.5,
      SettingsStore.musicVolumeKey: 'x',
      SettingsStore.themeModeKey: 'light',
      SettingsStore.paletteIdKey: 'plaid',
    });
    final m = mixed.loadSettings();
    expect(m.sfxVolume, 0.5);
    expect(m.musicVolume, 0.4);
    expect(m.themeMode, ThemeMode.light);
    expect(m.paletteId, PaletteId.classic);
  });

  test('an out of range volume is clamped, an int is accepted', () async {
    final store = await _open({
      SettingsStore.sfxVolumeKey: 3.5,
      SettingsStore.musicVolumeKey: -2,
    });
    final settings = store.loadSettings();
    expect(settings.sfxVolume, 1.0);
    expect(settings.musicVolume, 0.0);

    final whole = await _open({SettingsStore.sfxVolumeKey: 1});
    expect(whole.loadSettings().sfxVolume, 1.0);
  });

  test('not finite volumes fall back to the default', () async {
    final store = await _open({
      SettingsStore.sfxVolumeKey: double.nan,
      SettingsStore.musicVolumeKey: double.infinity,
    });
    final settings = store.loadSettings();
    expect(settings.sfxVolume, 0.8);
    expect(settings.musicVolume, 0.4);
  });

  test('the volume setters clamp and ignore NaN', () {
    final settings = GameSettings();
    var notified = 0;
    settings.addListener(() => notified++);
    settings.sfxVolume = 2;
    expect(settings.sfxVolume, 1.0);
    settings.sfxVolume = -1;
    expect(settings.sfxVolume, 0.0);
    settings.sfxVolume = double.nan;
    expect(settings.sfxVolume, 0.0);
    settings.musicVolume = 0.4; // unchanged: no notification
    expect(notified, 2);
    settings.musicVolume = 0.55;
    expect(settings.musicVolume, 0.55);
    expect(notified, 3);
  });

  test('the last setup round trips', () async {
    final store = await _open({});
    final setup = MatchSetup.hotSeat(
      players: 2,
      rules: const RulesConfig.strategic(),
    ).withSeat(2, const SeatConfig.ai(level: AiLevel.hard, name: 'Robo'));
    await store.saveSetup(setup);

    final again = SettingsStore(await SharedPreferences.getInstance());
    expect(again.loadSetup(), setup);
  });

  test('a bad stored setup falls back to the default table', () async {
    final unplayable = MatchSetup.hotSeat().withSeat(
      0,
      const SeatConfig(type: SeatType.remote),
    );
    final cases = <Object>[
      'not json {{{',
      jsonEncode([1, 2, 3]),
      jsonEncode(<String, Object?>{}),
      jsonEncode(<String, Object?>{'seats': 'nope'}),
      jsonEncode(unplayable.toJson()),
      42,
    ];
    for (final bad in cases) {
      final store = await _open({SettingsStore.setupKey: bad});
      expect(store.loadSetup(), MatchSetup.hotSeat(), reason: '$bad');
    }
  });
}
