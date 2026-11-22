import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pacing.dart' show AnimationSpeed;
import 'package:ludo/ui/core/palette_spec.dart' show PaletteId;
import 'package:ludo/ui/core/sfx.dart' show clampVolume;
import 'package:ludo/ui/core/table_layout.dart' show UiOrientation;

export 'package:flutter/material.dart' show ThemeMode;
export 'package:ludo/ui/core/pacing.dart' show AnimationSpeed;
export 'package:ludo/ui/core/palette_spec.dart' show PaletteId;
export 'package:ludo/ui/core/table_layout.dart' show UiOrientation;

/// Reduce-motion override: follow the system, or force it on / off.
enum ReduceMotion { system, on, off }

/// Default effects volume.
const double defaultSfxVolume = 0.8;

/// Default music volume.
const double defaultMusicVolume = 0.4;

/// User settings; every change notifies the screen. `SettingsStore` saves
/// them to disk and restores them at launch.
class GameSettings extends ChangeNotifier {
  GameSettings({
    bool haptics = true,
    ReduceMotion reduceMotion = ReduceMotion.system,
    UiOrientation orientation = UiOrientation.table,
    bool autoRotateShared = true,
    bool frameOverlay = false,
    bool sfxEnabled = true,
    double sfxVolume = defaultSfxVolume,
    bool musicEnabled = false,
    double musicVolume = defaultMusicVolume,
    ThemeMode themeMode = ThemeMode.system,
    PaletteId paletteId = PaletteId.classic,
    bool autoMoveSingle = false,
    AnimationSpeed animationSpeed = AnimationSpeed.normal,
  })  : _haptics = haptics,
        _reduceMotion = reduceMotion,
        _orientation = orientation,
        _autoRotateShared = autoRotateShared,
        _frameOverlay = frameOverlay,
        _sfxEnabled = sfxEnabled,
        _sfxVolume = _volume(sfxVolume, defaultSfxVolume),
        _musicEnabled = musicEnabled,
        _musicVolume = _volume(musicVolume, defaultMusicVolume),
        _themeMode = themeMode,
        _paletteId = paletteId,
        _autoMoveSingle = autoMoveSingle,
        _animationSpeed = animationSpeed;

  bool _haptics;
  ReduceMotion _reduceMotion;
  UiOrientation _orientation;
  bool _autoRotateShared;
  bool _frameOverlay;
  bool _sfxEnabled;
  double _sfxVolume;
  bool _musicEnabled;
  double _musicVolume;
  ThemeMode _themeMode;
  PaletteId _paletteId;
  bool _autoMoveSingle;
  AnimationSpeed _animationSpeed;

  /// A volume in `0..1`: out of range is clamped, not a number falls back.
  static double _volume(double v, double fallback) =>
      v.isFinite ? clampVolume(v) : fallback;

  bool get haptics => _haptics;
  ReduceMotion get reduceMotion => _reduceMotion;

  /// `Table`: text faces each seat. `Fixed`: everything upright.
  UiOrientation get orientation => _orientation;

  /// Turn the shared UI (menu, game-over card) toward the active seat. Only
  /// meaningful in table mode.
  bool get autoRotateShared => _autoRotateShared;

  /// Frame-timing overlay (profiling aid).
  bool get frameOverlay => _frameOverlay;

  /// Sound effects on or off.
  bool get sfxEnabled => _sfxEnabled;

  /// Effects volume, `0..1`.
  double get sfxVolume => _sfxVolume;

  /// Background music on or off (off by default).
  bool get musicEnabled => _musicEnabled;

  /// Music volume, `0..1`.
  double get musicVolume => _musicVolume;

  /// System, light or dark. Presentation only.
  ThemeMode get themeMode => _themeMode;

  /// The chosen palette. Presentation only.
  PaletteId get paletteId => _paletteId;

  /// A seat with exactly one legal move plays it without a tap. Off by
  /// default: a tap on the token previews the move, a second tap plays it.
  bool get autoMoveSingle => _autoMoveSingle;

  /// How fast hops, dice and effects play (and the AI thinks).
  AnimationSpeed get animationSpeed => _animationSpeed;

  set haptics(bool v) => _set(_haptics != v, () => _haptics = v);
  set reduceMotion(ReduceMotion v) =>
      _set(_reduceMotion != v, () => _reduceMotion = v);
  set orientation(UiOrientation v) =>
      _set(_orientation != v, () => _orientation = v);
  set autoRotateShared(bool v) =>
      _set(_autoRotateShared != v, () => _autoRotateShared = v);
  set frameOverlay(bool v) => _set(_frameOverlay != v, () => _frameOverlay = v);
  set sfxEnabled(bool v) => _set(_sfxEnabled != v, () => _sfxEnabled = v);
  set sfxVolume(double v) {
    final c = _volume(v, _sfxVolume);
    _set(_sfxVolume != c, () => _sfxVolume = c);
  }

  set musicEnabled(bool v) => _set(_musicEnabled != v, () => _musicEnabled = v);
  set musicVolume(double v) {
    final c = _volume(v, _musicVolume);
    _set(_musicVolume != c, () => _musicVolume = c);
  }

  set themeMode(ThemeMode v) => _set(_themeMode != v, () => _themeMode = v);
  set paletteId(PaletteId v) => _set(_paletteId != v, () => _paletteId = v);
  set autoMoveSingle(bool v) =>
      _set(_autoMoveSingle != v, () => _autoMoveSingle = v);
  set animationSpeed(AnimationSpeed v) =>
      _set(_animationSpeed != v, () => _animationSpeed = v);

  void _set(bool changed, VoidCallback apply) {
    if (changed) {
      apply();
      notifyListeners();
    }
  }

  static final MotionSpec _fast =
      MotionSpec.standard.scaled(AnimationSpeed.fast.factor);

  /// The motion spec to use given the platform's reduce-motion flag and the
  /// animation speed ([applySpeed] false for replays, which have their own
  /// speed control). Reduced motion ignores the speed: it is already brief.
  MotionSpec motionSpec({
    required bool systemReduced,
    bool applySpeed = true,
  }) {
    final reduced = switch (_reduceMotion) {
      ReduceMotion.system => systemReduced,
      ReduceMotion.on => true,
      ReduceMotion.off => false,
    };
    if (reduced) {
      return MotionSpec.reduced;
    }
    return applySpeed && _animationSpeed == AnimationSpeed.fast
        ? _fast
        : MotionSpec.standard;
  }
}
