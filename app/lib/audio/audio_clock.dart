import 'dart:async';

/// Time and timers for `AudioService`, so tests can run fades and delayed
/// cues on a fake clock.
abstract class AudioClock {
  /// Monotonic time in milliseconds.
  double nowMs();

  /// Runs [action] once after [delayMs].
  void after(double delayMs, void Function() action);

  /// Calls [tick] every [periodMs] until the returned function is called.
  void Function() every(double periodMs, void Function() tick);
}

/// The real clock: a stopwatch and `Timer`s.
class SystemAudioClock implements AudioClock {
  SystemAudioClock() {
    _watch.start();
  }

  final Stopwatch _watch = Stopwatch();

  @override
  double nowMs() => _watch.elapsedMicroseconds / 1000.0;

  @override
  void after(double delayMs, void Function() action) {
    Timer(Duration(microseconds: (delayMs * 1000).round()), action);
  }

  @override
  void Function() every(double periodMs, void Function() tick) {
    final timer = Timer.periodic(
      Duration(microseconds: (periodMs * 1000).round()),
      (_) => tick(),
    );
    return timer.cancel;
  }
}
