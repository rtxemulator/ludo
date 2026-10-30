import 'package:flutter/foundation.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/table_layout.dart' show UiOrientation;

export 'package:ludo/ui/core/table_layout.dart' show UiOrientation;

/// Reduce-motion override: follow the system, or force it on / off.
enum ReduceMotion { system, on, off }

/// User settings; every change notifies the screen. `SettingsStore` saves
/// them to disk and restores them at launch.
class GameSettings extends ChangeNotifier {
  GameSettings({
    bool haptics = true,
    ReduceMotion reduceMotion = ReduceMotion.system,
    UiOrientation orientation = UiOrientation.table,
    bool autoRotateShared = true,
    bool frameOverlay = false,
  })  : _haptics = haptics,
        _reduceMotion = reduceMotion,
        _orientation = orientation,
        _autoRotateShared = autoRotateShared,
        _frameOverlay = frameOverlay;

  bool _haptics;
  ReduceMotion _reduceMotion;
  UiOrientation _orientation;
  bool _autoRotateShared;
  bool _frameOverlay;

  bool get haptics => _haptics;
  ReduceMotion get reduceMotion => _reduceMotion;

  /// `Table`: text faces each seat. `Fixed`: everything upright.
  UiOrientation get orientation => _orientation;

  /// Turn the shared UI (menu, game-over card) toward the active seat. Only
  /// meaningful in table mode.
  bool get autoRotateShared => _autoRotateShared;

  /// Frame-timing overlay (profiling aid).
  bool get frameOverlay => _frameOverlay;

  set haptics(bool v) => _set(_haptics != v, () => _haptics = v);
  set reduceMotion(ReduceMotion v) =>
      _set(_reduceMotion != v, () => _reduceMotion = v);
  set orientation(UiOrientation v) =>
      _set(_orientation != v, () => _orientation = v);
  set autoRotateShared(bool v) =>
      _set(_autoRotateShared != v, () => _autoRotateShared = v);
  set frameOverlay(bool v) => _set(_frameOverlay != v, () => _frameOverlay = v);

  void _set(bool changed, VoidCallback apply) {
    if (changed) {
      apply();
      notifyListeners();
    }
  }

  /// The motion spec to use given the platform's reduce-motion flag.
  MotionSpec motionSpec({required bool systemReduced}) {
    final reduced = switch (_reduceMotion) {
      ReduceMotion.system => systemReduced,
      ReduceMotion.on => true,
      ReduceMotion.off => false,
    };
    return reduced ? MotionSpec.reduced : MotionSpec.standard;
  }
}
