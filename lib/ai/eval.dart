import 'package:ludo/engine/ludo_engine.dart';

import 'features.dart';
import 'weights.dart';

/// `V(state, unit) = S(unit) - mean(S(other units))`; a finished match
/// returns the placement value in the same shape. Positive is good for
/// [unit].
double evaluate(GameState s, int unit, AiWeights w) {
  if (s.isOver) {
    return terminalValue(s, unit);
  }
  final scores = unitScores(s, w);
  var others = 0.0;
  var count = 0;
  var seen = 0;
  for (final seat in s.activeSeats) {
    final u = s.unitOf(seat);
    if (u == unit || (seen >> u) & 1 == 1) {
      continue;
    }
    seen |= 1 << u;
    others += scores[u];
    count++;
  }
  return scores[unit] - (count == 0 ? 0 : others / count);
}

/// Value of a finished match for [unit]: its placement value minus the mean
/// of the others'.
double terminalValue(GameState s, int unit) {
  final units = s.units;
  final mine = _placement(s, unit, units.length);
  var others = 0.0;
  var count = 0;
  for (final u in units) {
    if (u != unit) {
      others += _placement(s, u, units.length);
      count++;
    }
  }
  return mine - (count == 0 ? 0 : others / count);
}

double _placement(GameState s, int unit, int unitCount) {
  final rank = s.ranking.indexWhere((seats) => s.unitOf(seats.first) == unit);
  if (rank < 0 || rank == unitCount - 1) {
    return 0;
  }
  return AiWeights.placement[rank];
}
