/// A clock that runs [speed] times faster than a base clock, without jumping
/// when the speed changes. The replay viewer hands it to the table so every
/// animation (hops, rings, tray chips) plays at 1x, 2x or 4x.
///
/// Times are in milliseconds, like the frame clock of the game controller.
class ScaledClock {
  ScaledClock(double Function() base, {double speed = 1})
      : assert(speed > 0),
        _base = base,
        _speed = speed,
        _lastBase = base();

  final double Function() _base;
  double _speed;
  double _lastBase;
  double _virtual = 0;

  /// The scaled time: starts at 0 and advances `speed` times as fast as the
  /// base clock.
  double now() {
    final b = _base();
    _virtual += (b - _lastBase) * _speed;
    _lastBase = b;
    return _virtual;
  }

  double get speed => _speed;

  /// Changes the speed from now on; time already passed keeps its length.
  set speed(double value) {
    assert(value > 0);
    now();
    _speed = value;
  }
}
