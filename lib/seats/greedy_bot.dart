import 'package:ludo/engine/ludo_engine.dart';

/// The baseline computer player: a one-move greedy heuristic (the blueprint's
/// "Easy" tier). It reads only the public game state and never the dice, so
/// it plays fair. Every AI seat uses it until the expectiminimax tiers
/// arrive in Milestone 4; the choice is deterministic (ties go to the first
/// legal move).
class GreedyBot {
  const GreedyBot();

  // Weights, in "squares of progress" units.
  static const double captureBonus = 25;
  static const double victimWeight = 1.5;
  static const double homeBonus = 20;
  static const double leaveYardBonus = 10;
  static const double safeSquareBonus = 4;
  static const double dangerPenalty = 9;
  static const double escapeBonus = 6;

  /// Picks one of [legal] (the moves `Engine.legalMoves` gave for [state]).
  Move choose(GameState state, List<Move> legal) {
    if (legal.isEmpty) {
      throw ArgumentError.value(legal, 'legal', 'no legal moves to choose');
    }
    var best = legal.first;
    var bestScore = score(state, best);
    for (final move in legal.skip(1)) {
      final s = score(state, move);
      if (s > bestScore) {
        best = move;
        bestScore = s;
      }
    }
    return best;
  }

  /// How good [move] looks in [state] (higher is better).
  double score(GameState state, Move move) {
    final after = Engine.apply(state, move);
    final mine = state.seatsOfUnit(state.unitOf(move.owner)).toSet();
    var value = (_progress(move.to) - _progress(move.from)).toDouble();

    // Captures: every opponent token that went back to its yard.
    for (final seat in state.activeSeats) {
      if (mine.contains(seat)) {
        continue;
      }
      for (var i = 0; i < tokensPerSeat; i++) {
        final was = state.tokens[seat][i];
        if (was != yardPosition && after.tokens[seat][i] == yardPosition) {
          value += captureBonus + victimWeight * _progress(was);
        }
      }
    }

    if (move.to == finishPosition) {
      value += homeBonus;
    }
    if (move.from == yardPosition) {
      value += leaveYardBonus;
    }

    // Safety of the destination (and of the square it leaves).
    if (isOnTrack(move.to)) {
      final square = absoluteSquare(move.owner, move.to);
      if (isSafeSquare(square)) {
        value += safeSquareBonus;
      } else if (_threatened(state, mine, square)) {
        value -= dangerPenalty;
      }
    }
    if (isOnTrack(move.from)) {
      final square = absoluteSquare(move.owner, move.from);
      if (!isSafeSquare(square) && _threatened(state, mine, square)) {
        value += escapeBonus;
      }
    }
    return value;
  }

  /// Squares walked: yard 0, start 1, ... finish 57.
  static int _progress(int position) => position + 1;

  /// Whether an opponent token stands 1 to 6 squares behind [square].
  static bool _threatened(GameState state, Set<int> mine, int square) {
    for (final seat in state.activeSeats) {
      if (mine.contains(seat)) {
        continue;
      }
      for (final position in state.tokens[seat]) {
        if (!isOnTrack(position)) {
          continue;
        }
        final behind = (square - absoluteSquare(seat, position)) % trackSquares;
        if (behind >= 1 && behind <= 6) {
          return true;
        }
      }
    }
    return false;
  }
}
