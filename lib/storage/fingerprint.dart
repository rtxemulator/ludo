import 'package:ludo/engine/ludo_engine.dart';

/// A stable 64-bit fingerprint of a [GameState], as 16 lowercase hex digits.
///
/// FNV-1a over the integers that define the game (not `Object.hash`, which
/// is not stable between runs). A save stores the fingerprint of the state
/// after its last decision; a replay that ends elsewhere means the engine
/// changed under the log (or the save was altered).
abstract final class StateFingerprint {
  static const int _offset = 0xcbf29ce484222325;
  static const int _prime = 0x100000001b3;

  static String of(GameState state) {
    var h = _offset;

    void mix(int value) {
      for (var i = 0; i < 8; i++) {
        h = (h ^ ((value >>> (8 * i)) & 0xFF)) * _prime;
      }
    }

    void mixAll(Iterable<int> values) {
      final list = values.toList();
      mix(list.length);
      list.forEach(mix);
    }

    mix(state.currentSeat);
    mix(state.dice ?? -1);
    mix(state.consecutiveSixes);
    mix(state.rngState);
    mix(state.turnNumber);
    mix(state.bankPhase.index);
    mixAll(state.activeSeats);
    for (final seat in state.tokens) {
      mixAll(seat);
    }
    for (final seat in state.rest) {
      mixAll(seat);
    }
    mixAll(state.finishOrder);
    mixAll(state.bank);
    return _hex(h);
  }

  static String _hex(int h) {
    final hi = (h >>> 32).toRadixString(16).padLeft(8, '0');
    final lo = (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '$hi$lo';
  }
}
