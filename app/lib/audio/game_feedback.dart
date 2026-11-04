import 'package:ludo/ui/core/haptics.dart';
import 'package:ludo/ui/core/sfx.dart';

import '../haptics/haptics_service.dart';
import 'audio_service.dart';

/// The one place that plays a haptic and its sound together.
///
/// `GameController` calls [play] where it used to call the haptics service
/// directly, so the timing of every call site is unchanged. [sound] is for
/// sounds with no haptic (the hop).
class GameFeedback {
  GameFeedback({required this.haptics, this.audio});

  final HapticsService haptics;

  /// App-wide audio; null in tests that do not care about sound.
  final AudioService? audio;

  bool _soundMuted = false;

  /// The haptics switch (kept as `enabled` for the existing code and tests).
  bool get enabled => haptics.enabled;
  set enabled(bool v) => haptics.enabled = v;

  /// Replay at 2x or 4x mutes the effects; scrubbing and jumping play
  /// nothing. Muting also drops cues that are still waiting.
  bool get soundMuted => _soundMuted;
  set soundMuted(bool v) {
    _soundMuted = v;
    if (v) {
      cancelSounds();
    }
  }

  /// Haptic plus its sound.
  void play(HapticEvent event) {
    haptics.play(event);
    if (!_soundMuted) {
      audio?.playHaptic(event);
    }
  }

  /// A sound with no haptic.
  void sound(SfxEvent event) {
    if (!_soundMuted) {
      audio?.play(event);
    }
  }

  /// Drops delayed cues (a scrub or a jump).
  void cancelSounds() => audio?.cancelPending();

  void dispose() => haptics.dispose();
}
