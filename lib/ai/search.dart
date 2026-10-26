import 'package:ludo/engine/ludo_engine.dart';

import 'eval.dart';
import 'position_key.dart';
import 'weights.dart';

/// Limits on one decision. The app uses [maxMillis]; tests and tournaments
/// use [maxNodes] only, so their results are reproducible.
class AiBudget {
  const AiBudget({this.maxMillis, this.maxNodes});

  final int? maxMillis;
  final int? maxNodes;
}

class _Abort implements Exception {
  const _Abort();
}

/// Expectimax with modelled opponents (`docs/ludo-ai.md` sections 2-3).
///
/// * My decision nodes maximise; chance nodes average the six faces, built
///   with `Engine.applyRoll` and explicit faces (the PRNG is never read).
/// * With two units the opponent minimises; with three or four it plays its
///   one-ply best reply under its own evaluation.
/// * Depth counts finished turns of other units; bonus rolls stay inside a
///   turn, capped at [bonusDepth] extra chance levels.
/// * Iterative deepening to [maxDepth]; the best move of the last completed
///   depth is returned when the budget runs out.
/// * Banked rolls: equal boards reached by different spending orders share
///   one transposition entry, and a capture/home bonus sequence adds a flat
///   `bonusRollValue` instead of being expanded.
///
/// No randomness: ties go to the first (lowest token index) move.
class AiSearch {
  AiSearch({
    required this.maxDepth,
    this.bonusDepth = 1,
    this.beam,
    this.budget = const AiBudget(),
    this.weights = AiWeights.tuned,
  });

  final int maxDepth;
  final int bonusDepth;

  /// Children kept at inner nodes (null: all).
  final int? beam;
  final AiBudget budget;
  final AiWeights weights;

  /// Statistics of the last [choose].
  int nodes = 0;
  int depthReached = 0;

  final Map<int, double> _memo = {};
  final Stopwatch _clock = Stopwatch();
  int _rootUnit = 0;
  int _opponents = 1;
  int _depth = 1;

  /// Picks one of [legal] (the moves `Engine.legalMoves` returned for
  /// [state]); the result is always an element of that list.
  Move choose(GameState state, List<Move> legal) {
    if (legal.isEmpty) {
      throw ArgumentError.value(legal, 'legal', 'no legal moves to choose');
    }
    nodes = 0;
    depthReached = 0;
    final root = _collapse(state, legal);
    if (root.length == 1) {
      return root.first;
    }
    _rootUnit = state.unitOf(state.currentSeat);
    _opponents = state.units.length - 1;
    _clock
      ..reset()
      ..start();

    // One-ply fallback in case even depth 1 cannot finish.
    var best = root.first;
    var bestValue = double.negativeInfinity;
    for (final m in root) {
      final v = evaluate(Engine.applyLegal(state, m), _rootUnit, weights);
      if (v > bestValue) {
        best = m;
        bestValue = v;
      }
    }

    for (var d = 1; d <= maxDepth; d++) {
      _depth = d;
      _memo.clear();
      try {
        var iterBest = root.first;
        var iterValue = double.negativeInfinity;
        for (final m in root) {
          final child = Engine.applyLegal(state, m);
          final (done, bonus) = _afterMove(state, child, 0, 0);
          final v = _value(child, done, bonus, 1);
          if (v > iterValue) {
            iterBest = m;
            iterValue = v;
          }
        }
        best = iterBest;
        depthReached = d;
      } on _Abort {
        break;
      }
    }
    return best;
  }

  // ---- Nodes --------------------------------------------------------------

  double _value(GameState s, int done, int bonus, double prob) {
    if (s.isOver) {
      return terminalValue(s, _rootUnit);
    }
    if (done >= _depth) {
      return _leaf(s);
    }
    _tick();
    final banked = s.rules.bankedRolls;
    if (!banked && s.awaitingRoll && bonus > bonusDepth) {
      return _leaf(s);
    }
    final key = positionKey(s, done, bonus);
    final cached = _memo[key];
    if (cached != null) {
      return cached;
    }
    final double v;
    if (s.awaitingMove) {
      v = _decision(s, done, bonus, prob);
    } else if (banked && s.turnSnapshot != null) {
      v = _bankedBonus(s, done, bonus, prob);
    } else {
      v = _chance(s, done, bonus, prob);
    }
    _memo[key] = v;
    return v;
  }

  /// Banked mode, rolling phase after a capture/home move in the middle of a
  /// turn: skip the bonus dice, credit a flat value to the mover's unit and
  /// go on spending what is left of the bank.
  double _bankedBonus(GameState s, int done, int bonus, double prob) {
    final mover = s.unitOf(s.currentSeat);
    final credit = mover == _rootUnit
        ? weights.bonusRollValue
        : -weights.bonusRollValue / _opponents;
    if (s.bank.isEmpty) {
      return _leaf(s) + credit;
    }
    final moving = s.copyWith(bankPhase: BankPhase.moving);
    return _value(moving, done, bonus, prob) + credit;
  }

  double _chance(GameState s, int done, int bonus, double prob) {
    var sum = 0.0;
    var kept = 0;
    for (var face = 1; face <= 6; face++) {
      final p = prob / 6;
      if (p < 0.005) {
        continue; // a rare third-level six: dropped, the rest renormalised
      }
      _tick();
      // The state's own PRNG is neither read nor advanced.
      final r = Engine.applyRoll(s, DiceRoll(face, 0));
      final (d2, b2) = _afterRoll(s, r.state, done, bonus);
      sum += _value(r.state, d2, b2, p);
      kept++;
    }
    return kept == 0 ? _leaf(s) : sum / kept;
  }

  double _decision(GameState s, int done, int bonus, double prob) {
    final legal = Engine.legalMoves(s);
    if (legal.isEmpty) {
      return _leaf(s);
    }
    final moves = _collapse(s, legal);
    final mover = s.unitOf(s.currentSeat);
    final mine = mover == _rootUnit;

    final children = <(double, Move, GameState)>[];
    for (final m in moves) {
      _tick();
      final child = Engine.applyLegal(s, m);
      children.add((evaluate(child, mover, weights), m, child));
    }
    if (children.length > 1) {
      // Best first for the mover; stable, so ties keep the lowest token.
      final indexed = [
        for (var i = 0; i < children.length; i++) (i, children[i])
      ];
      indexed.sort((a, b) {
        final c = b.$2.$1.compareTo(a.$2.$1);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      children
        ..clear()
        ..addAll(indexed.map((e) => e.$2));
    }

    final limit = mine || _opponents == 1
        ? (beam == null ? children.length : beam!.clamp(1, children.length))
        : 1; // several opponents: one-ply best reply only
    var best = mine ? double.negativeInfinity : double.infinity;
    for (var i = 0; i < limit; i++) {
      final child = children[i].$3;
      final (d2, b2) = _afterMove(s, child, done, bonus);
      final v = _value(child, d2, b2, prob);
      if (!mine && _opponents > 1) {
        best = v; // the one reply it would play, whatever that is worth to me
      } else if (mine ? v > best : v < best) {
        best = v;
      }
    }
    return best;
  }

  // ---- Helpers ------------------------------------------------------------

  double _leaf(GameState s) => evaluate(s, _rootUnit, weights);

  void _tick() {
    nodes++;
    final max = budget.maxNodes;
    if (max != null && nodes > max) {
      throw const _Abort();
    }
    final ms = budget.maxMillis;
    if (ms != null && (nodes & 31) == 0 && _clock.elapsedMilliseconds >= ms) {
      throw const _Abort();
    }
  }

  (int, int) _afterMove(GameState prev, GameState next, int done, int bonus) {
    if (next.turnNumber != prev.turnNumber) {
      return (prev.unitOf(prev.currentSeat) == _rootUnit ? done : done + 1, 0);
    }
    return (done, bonus + 1);
  }

  (int, int) _afterRoll(GameState prev, GameState next, int done, int bonus) {
    if (next.turnNumber != prev.turnNumber) {
      return (prev.unitOf(prev.currentSeat) == _rootUnit ? done : done + 1, 0);
    }
    return (done, bonus);
  }

  /// One representative per distinct effect: tokens on the same square (and
  /// equal banked dice) give the same result, so only the first (lowest
  /// token index) is kept. Order is preserved.
  List<Move> _collapse(GameState s, List<Move> legal) {
    if (legal.length < 2) {
      return legal;
    }
    final seen = <int>{};
    final out = <Move>[];
    for (final m in legal) {
      final die = s.rules.bankedRolls && m.dieIndex < s.bank.length
          ? s.bank[m.dieIndex]
          : 0;
      final sig = ((((m.owner * 64 + m.from + 1) * 64 + m.to + 1) * 8 +
                  m.partnerIndex +
                  1) *
              8) +
          die;
      if (seen.add(sig)) {
        out.add(m);
      }
    }
    return out;
  }
}
