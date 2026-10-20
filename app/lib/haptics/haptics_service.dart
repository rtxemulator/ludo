import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ludo/ui/core/haptics.dart';

/// Plays [HapticEvent]s through a small native channel
/// (`android/.../MainActivity.kt`) that uses `VibrationEffect` directly.
///
/// Flutter's `HapticFeedback` goes through `performHapticFeedback`, which many
/// phones silence when system touch feedback is off and which cannot express
/// strength; it is kept only as a fallback.
///
/// All logic (patterns, rate limit, toggle) lives in the pure
/// `HapticPlayer`; this class only binds it to the channel and to timers.
class HapticsService {
  HapticsService({MethodChannel? channel, double Function()? now})
      : _channel = channel ?? const MethodChannel(channelName) {
    _player = HapticPlayer(
      emit: (pulse) => unawaited(_vibrate(pulse)),
      schedule: (delayMs, action) =>
          Timer(Duration(microseconds: (delayMs * 1000).round()), action),
      nowMs: now ?? _stopwatchClock(),
    );
  }

  static const String channelName = 'dev.ludo/haptics';

  static double Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds / 1000.0;
  }

  final MethodChannel _channel;
  late final HapticPlayer _player;

  /// Global haptics toggle.
  bool get enabled => _player.enabled;
  set enabled(bool value) => _player.enabled = value;

  void play(HapticEvent event) => _player.play(event);

  /// Whether the native side found a vibrator (`false` when the channel is
  /// missing, e.g. in tests).
  Future<bool> isNativeAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _vibrate(HapticPulse pulse) async {
    try {
      final ok = await _channel.invokeMethod<bool>('pulse', <String, Object>{
        'kind': pulse.kind.name,
        'strength': pulse.strength,
      });
      if (ok == true) {
        return;
      }
    } catch (_) {
      // Channel missing or failed: fall through to the framework haptics.
    }
    try {
      switch (pulse.kind) {
        case HapticKind.tick:
          await HapticFeedback.selectionClick();
        case HapticKind.click:
          await HapticFeedback.mediumImpact();
        case HapticKind.heavy:
          await HapticFeedback.heavyImpact();
      }
    } catch (_) {
      // Nothing more we can do.
    }
  }

  /// Stops pending pulses from firing.
  void dispose() => _player.enabled = false;
}
