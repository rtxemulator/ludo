import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';

const List<int> allSeats = [0, 1, 2, 3];

/// Relative position, from the point of view of [seat], of absolute [square].
int relativeFor(int seat, int square) => (square - seat * 13) % 52;

/// Builds a state with explicit token positions.
///
/// Seats missing from [tokens] have all tokens in the yard.
GameState makeState({
  RulesConfig rules = const RulesConfig(),
  List<int> activeSeats = allSeats,
  Map<int, List<int>> tokens = const {},
  int currentSeat = 0,
  int? dice,
  int consecutiveSixes = 0,
  int rngState = 1,
  int turnNumber = 0,
  List<int> finishOrder = const [],
  List<int> bank = const [],
  BankPhase bankPhase = BankPhase.rolling,
  TurnSnapshot? turnSnapshot,
}) {
  return GameState(
    tokens: [
      for (var s = 0; s < 4; s++) tokens[s] ?? List<int>.filled(4, -1),
    ],
    rules: rules,
    activeSeats: activeSeats,
    currentSeat: currentSeat,
    dice: dice,
    consecutiveSixes: consecutiveSixes,
    rngState: rngState,
    turnNumber: turnNumber,
    finishOrder: finishOrder,
    bank: bank,
    bankPhase: bankPhase,
    turnSnapshot: turnSnapshot,
  );
}

/// Replaces some seats' tokens (and optionally seat / die) of [state].
GameState withTokens(
  GameState state,
  Map<int, List<int>> replacements, {
  int? currentSeat,
  int? dice,
}) {
  return state.copyWith(
    tokens: [
      for (var s = 0; s < 4; s++) replacements[s] ?? state.tokens[s],
    ],
    currentSeat: currentSeat,
    dice: dice,
  );
}

/// Applies the legal move of [tokenIndex] in [state].
GameState play(GameState state, int tokenIndex) {
  final move = Engine.legalMoves(state).singleWhere(
    (m) => m.tokenIndex == tokenIndex,
    orElse: () => throw StateError('Token $tokenIndex has no legal move'),
  );
  return Engine.apply(state, move);
}

/// Whether [tokenIndex] has a legal move in [state] (optionally with an
/// explicit [dice]).
bool canMove(GameState state, int tokenIndex, [int? dice]) =>
    Engine.legalMoves(state, dice).any((m) => m.tokenIndex == tokenIndex);

/// Finds a PRNG state whose next rolls are exactly [sequence].
int findRngState(List<int> sequence) {
  for (var candidate = 0; candidate < 5000000; candidate++) {
    var state = candidate;
    var ok = true;
    for (final expected in sequence) {
      final roll = Dice.roll(state);
      if (roll.value != expected) {
        ok = false;
        break;
      }
      state = roll.nextState;
    }
    if (ok) {
      return candidate;
    }
  }
  throw StateError('No rng state found for $sequence');
}

class PlayResult {
  const PlayResult(
    this.state,
    this.log,
    this.afterMoves,
    this.steps,
    this.finished,
  );

  final GameState state;
  final List<MoveLogEntry> log;

  /// `afterMoves[k]` is the live state right after decision `k` was applied.
  final List<GameState> afterMoves;
  final int steps;
  final bool finished;
}

/// Plays a whole game with uniformly random choices from [chooser].
PlayResult playOut({
  required int seed,
  required Random chooser,
  RulesConfig rules = const RulesConfig(),
  List<int> activeSeats = allSeats,
  int maxSteps = 100000,
  void Function(GameState state)? onState,
}) {
  var state =
      Engine.newGame(seed: seed, rules: rules, activeSeats: activeSeats);
  final log = <MoveLogEntry>[];
  final afterMoves = <GameState>[];
  var steps = 0;
  while (!state.isOver) {
    if (steps++ >= maxSteps) {
      return PlayResult(state, log, afterMoves, steps, false);
    }
    if (!state.awaitingMove) {
      final rolled = Engine.roll(state);
      state = rolled.state;
      onState?.call(state);
      if (rolled.outcome != RollOutcome.awaitingMove) {
        continue;
      }
    }
    final moves = Engine.legalMoves(state);
    final move = moves[chooser.nextInt(moves.length)];
    log.add(Engine.logEntry(state, move));
    state = Engine.apply(state, move);
    afterMoves.add(state);
    onState?.call(state);
  }
  return PlayResult(state, log, afterMoves, steps, true);
}

/// Banked-rules variant of [makeState]: a state in the moving phase holding
/// [bank], with a snapshot of the board it started from.
GameState makeMoving({
  required List<int> bank,
  RulesConfig rules = const RulesConfig(bankedRolls: true),
  Map<int, List<int>> tokens = const {},
  int currentSeat = 0,
  List<int> activeSeats = allSeats,
}) {
  final base = makeState(
    rules: rules,
    tokens: tokens,
    currentSeat: currentSeat,
    activeSeats: activeSeats,
  );
  return base.copyWith(
    bank: bank,
    bankPhase: BankPhase.moving,
    turnSnapshot: TurnSnapshot(
      tokens: base.tokens,
      finishOrder: base.finishOrder,
      bank: bank,
    ),
  );
}

/// Rolls once per value in [values] after seeding the PRNG so the dice come
/// out exactly as listed; returns every [RollResult] in order.
List<RollResult> rollSequence(GameState state, List<int> values) {
  var current = state.copyWith(rngState: findRngState(values));
  final results = <RollResult>[];
  for (final _ in values) {
    final result = Engine.roll(current);
    results.add(result);
    current = result.state;
  }
  return results;
}

/// [state] with the PRNG seeded so the next rolls are exactly [values].
GameState withDice(GameState state, List<int> values) =>
    state.copyWith(rngState: findRngState(values));
