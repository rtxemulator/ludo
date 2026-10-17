import 'package:ludo/engine/ludo_engine.dart';

/// Tiny deterministic random source for visuals (dice yaw, sparks,
/// confetti). It reuses the engine's SplitMix64 step but has its own state,
/// so it can never disturb the game's dice PRNG.
class Seeded {
  Seeded(int seed) : _state = seed;

  int _state;

  /// Uniform in `[0, 1)`.
  double next() {
    final step = Dice.nextRaw(_state);
    _state = step.next;
    return (step.output >>> 11) / 9007199254740992.0; // 2^53
  }

  /// Uniform in `[lo, hi)`.
  double range(double lo, double hi) => lo + (hi - lo) * next();

  /// Uniform in `[-a, a)`.
  double spread(double a) => range(-a, a);
}
