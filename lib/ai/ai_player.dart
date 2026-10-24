import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';

import 'search.dart';
import 'weights.dart';

/// A computer player of a given [AiLevel]: `choose(state, legal)` keeps the
/// `GreedyBot` signature, so tests and tournaments run it synchronously and
/// the worker isolate wraps the very same function.
///
/// Easy is the untouched `GreedyBot`; Medium, Hard and Expert are
/// [AiSearch] with the tier table of `docs/ludo-ai.md` section 2. Fair by
/// construction: only public state is read, never the dice generator or its
/// state (guarded by `test/ai/ai_fairness_test.dart`).
class AiPlayer {
  AiPlayer(this.level, {AiBudget? budget, this.weights = AiWeights.tuned})
      : _search = _build(level, budget, weights);

  final AiLevel level;
  final AiWeights weights;
  final AiSearch? _search;

  static const GreedyBot _greedy = GreedyBot();

  /// Default wall-clock budgets in milliseconds (design doc D5).
  static const Map<AiLevel, int> defaultMillis = {
    AiLevel.medium: 40,
    AiLevel.hard: 100,
    AiLevel.expert: 250,
  };

  /// A player limited by node count only (deterministic; for tests and
  /// tournaments).
  AiPlayer.nodes(AiLevel level, int maxNodes,
      {AiWeights weights = AiWeights.tuned})
      : this(level, budget: AiBudget(maxNodes: maxNodes), weights: weights);

  static AiSearch? _build(AiLevel level, AiBudget? budget, AiWeights w) {
    switch (level) {
      case AiLevel.easy:
        return null;
      case AiLevel.medium:
        return AiSearch(
          maxDepth: 1,
          budget: budget ?? const AiBudget(maxMillis: 40),
          weights: w,
        );
      case AiLevel.hard:
        return AiSearch(
          maxDepth: 2,
          beam: 3,
          budget: budget ?? const AiBudget(maxMillis: 100),
          weights: w,
        );
      case AiLevel.expert:
        return AiSearch(
          maxDepth: 4,
          beam: 3,
          bonusDepth: 2,
          budget: budget ?? const AiBudget(maxMillis: 250),
          weights: w,
        );
    }
  }

  /// Nodes searched by the last [choose] (0 for Easy).
  int get lastNodes => _search?.nodes ?? 0;

  /// Depth completed by the last [choose] (0 for Easy or a forced move).
  int get lastDepth => _search?.depthReached ?? 0;

  /// Picks one of [legal] (the moves `Engine.legalMoves` gave for [state]).
  Move choose(GameState state, List<Move> legal) {
    final search = _search;
    if (search == null) {
      return _greedy.choose(state, legal);
    }
    return search.choose(state, legal);
  }
}
