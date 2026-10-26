import 'package:ludo/engine/ludo_engine.dart';

/// A 64-bit key for the search's transposition table: token positions (the
/// tokens of a seat are interchangeable, so they are sorted), seat to move,
/// pending die or bank, six counter, waiting counters, plus the search's own
/// [done] / [bonus] counters. Deliberately ignores the dice generator state, `turnNumber`
/// and the snapshot, which differ between equal positions.
///
/// It is a hash: a collision is possible in theory (about 2^-40 per lookup
/// pair) and would only blur one search value, never produce an illegal move.
int positionKey(GameState s, int done, int bonus) {
  var h = 0xcbf29ce484222325;
  int mix(int v) {
    h = (h ^ v) * 0x100000001b3;
    h ^= h >>> 29;
    return h;
  }

  var anyRest = false;
  for (final row in s.rest) {
    for (final r in row) {
      if (r != 0) {
        anyRest = true;
      }
    }
  }
  for (final seat in s.activeSeats) {
    final row = s.tokens[seat];
    if (anyRest) {
      for (var i = 0; i < tokensPerSeat; i++) {
        mix(row[i] * 8 + s.rest[seat][i]);
      }
    } else {
      var a = row[0], b = row[1], c = row[2], d = row[3];
      int t;
      if (a > b) (a, b) = (b, a);
      if (c > d) (c, d) = (d, c);
      if (a > c) (a, c) = (c, a);
      if (b > d) (b, d) = (d, b);
      if (b > c) {
        t = b;
        b = c;
        c = t;
      }
      mix(a);
      mix(b);
      mix(c);
      mix(d);
    }
  }
  mix(s.currentSeat);
  mix(s.dice ?? 9);
  mix(s.consecutiveSixes);
  mix(s.bankPhase.index);
  for (final d in s.bank) {
    mix(d + 16);
  }
  mix(done * 16 + bonus);
  return h;
}
