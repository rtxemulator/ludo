import 'sha256.dart';

/// Result of a single die roll: the face value and the advanced PRNG state.
class DiceRoll {
  const DiceRoll(this.value, this.nextState);

  /// Face value, `1..6`.
  final int value;

  /// PRNG state to store in `GameState.rngState` after this roll.
  final int nextState;

  @override
  String toString() => 'DiceRoll($value)';
}

/// Seeded, serializable dice PRNG plus the commit-reveal helpers used for
/// provably fair peer-to-peer dice.
///
/// The generator is SplitMix64: its whole state is one 64-bit integer, so a
/// game can be saved, replayed and synchronised from `seed + moveLog` alone.
abstract final class Dice {
  static const int _gamma = 0x9E3779B97F4A7C15;
  static const int _mulA = 0xBF58476D1CE4E5B9;
  static const int _mulB = 0x94D049BB133111EB;

  // 2^32 - (2^32 mod 6): values at or above this are rejected to avoid
  // modulo bias.
  static const int _rejectionLimit = 4294967292;

  /// One raw SplitMix64 step: returns the 64-bit [output] and the [next]
  /// state.
  static ({int output, int next}) nextRaw(int state) {
    final next = state + _gamma;
    var z = next;
    z = (z ^ (z >>> 30)) * _mulA;
    z = (z ^ (z >>> 27)) * _mulB;
    z = z ^ (z >>> 31);
    return (output: z, next: next);
  }

  /// Rolls an unbiased die (`1..6`) from [rngState].
  ///
  /// Pure function: the same state always yields the same roll.
  static DiceRoll roll(int rngState) {
    var state = rngState;
    while (true) {
      final step = nextRaw(state);
      state = step.next;
      final v = step.output >>> 32;
      if (v < _rejectionLimit) {
        return DiceRoll(v % 6 + 1, state);
      }
    }
  }

  // ---- Commit-reveal (provably fair dice) --------------------------------

  /// Combines the two revealed peer seeds into the shared roll seed.
  static int combineSeeds(int seedA, int seedB) => seedA ^ seedB;

  /// Hash commitment `H(seed)` (hex SHA-256 of the 8-byte big-endian seed).
  static String commit(int seed) => toHex(sha256(_seedBytes(seed)));

  /// Whether [seed] matches a previously received [commitment].
  static bool verify(int seed, String commitment) =>
      commit(seed) == commitment.toLowerCase();

  static List<int> _seedBytes(int seed) =>
      [for (var i = 7; i >= 0; i--) (seed >>> (i * 8)) & 0xFF];
}
