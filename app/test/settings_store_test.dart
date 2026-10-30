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
    );
    await store.saveSettings(settings);

    final again = SettingsStore(await SharedPreferences.getInstance());
    final loaded = again.loadSettings();
    expect(loaded.haptics, isFalse);
    expect(loaded.reduceMotion, ReduceMotion.on);
    expect(loaded.orientation, UiOrientation.fixed);
    expect(loaded.autoRotateShared, isFalse);
    expect(loaded.frameOverlay, isTrue);
  });

  test('a bound settings object is saved after every change', () async {
    final store = await _open({});
    final settings = store.loadSettings();
    final stop = store.bind(settings);
    settings.haptics = false;
    settings.reduceMotion = ReduceMotion.off;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final loaded = store.loadSettings();
    expect(loaded.haptics, isFalse);
    expect(loaded.reduceMotion, ReduceMotion.off);

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
