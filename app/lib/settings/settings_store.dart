import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ludo/seats/seats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_settings.dart';

/// Persists [GameSettings] and the last [MatchSetup] with
/// `shared_preferences`.
///
/// Reading never throws: a missing, mistyped or unknown value falls back to
/// its default, and a setup that cannot be played falls back to the default
/// hot-seat table. Writing is fire-and-forget (it never blocks painting).
class SettingsStore {
  SettingsStore(this._prefs);

  /// Opens the platform store.
  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const String hapticsKey = 'settings.haptics';
  static const String reduceMotionKey = 'settings.reduceMotion';
  static const String orientationKey = 'settings.orientation';
  static const String autoRotateKey = 'settings.autoRotateShared';
  static const String frameOverlayKey = 'settings.frameOverlay';
  static const String setupKey = 'setup.last';

  /// The saved settings, defaults for anything missing or bad.
  GameSettings loadSettings() {
    return GameSettings(
      haptics: _bool(hapticsKey) ?? true,
      reduceMotion:
          _enum(reduceMotionKey, ReduceMotion.values) ?? ReduceMotion.system,
      orientation:
          _enum(orientationKey, UiOrientation.values) ?? UiOrientation.table,
      autoRotateShared: _bool(autoRotateKey) ?? true,
      frameOverlay: _bool(frameOverlayKey) ?? false,
    );
  }

  /// Saves every field of [settings].
  Future<void> saveSettings(GameSettings settings) async {
    try {
      await _prefs.setBool(hapticsKey, settings.haptics);
      await _prefs.setString(reduceMotionKey, settings.reduceMotion.name);
      await _prefs.setString(orientationKey, settings.orientation.name);
      await _prefs.setBool(autoRotateKey, settings.autoRotateShared);
      await _prefs.setBool(frameOverlayKey, settings.frameOverlay);
    } on Object catch (e) {
      debugPrint('Could not save settings: $e');
    }
  }

  /// Saves [settings] now and after every change; returns the stop function.
  VoidCallback bind(GameSettings settings) {
    void save() => saveSettings(settings);
    settings.addListener(save);
    return () => settings.removeListener(save);
  }

  /// The last setup played or edited, or the default table.
  MatchSetup loadSetup() {
    try {
      final text = _prefs.get(setupKey);
      if (text is! String) {
        return MatchSetup.hotSeat();
      }
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) {
        return MatchSetup.hotSeat();
      }
      final setup = MatchSetup.fromJson(json);
      return setup.problems().isEmpty ? setup : MatchSetup.hotSeat();
    } on Object {
      return MatchSetup.hotSeat();
    }
  }

  /// Saves [setup] as the last one.
  Future<void> saveSetup(MatchSetup setup) async {
    try {
      await _prefs.setString(setupKey, jsonEncode(setup.toJson()));
    } on Object catch (e) {
      debugPrint('Could not save the setup: $e');
    }
  }

  bool? _bool(String key) {
    try {
      final value = _prefs.get(key);
      return value is bool ? value : null;
    } on Object {
      return null;
    }
  }

  T? _enum<T extends Enum>(String key, List<T> values) {
    try {
      final value = _prefs.get(key);
      if (value is! String) {
        return null;
      }
      for (final candidate in values) {
        if (candidate.name == value) {
          return candidate;
        }
      }
    } on Object {
      return null;
    }
    return null;
  }
}
