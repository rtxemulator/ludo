import 'board.dart';
import 'dice.dart';
import 'game_state.dart';
import 'move.dart';
import 'rules_config.dart';

/// Thrown when a move is not legal in the current state.
///
/// Network peers use this to reject illegal moves from the other side.
class IllegalMoveException implements Exception {
  const IllegalMoveException(this.message);

  final String message;

  @override
  String toString() => 'IllegalMoveException: $message';
}

/// What happened when the die was rolled.
enum RollOutcome {
  /// At least one legal move exists; the seat controller must pick one.
  awaitingMove,

  /// The roll produced no legal move; the turn passed automatically.
  noLegalMoves,

  /// Third consecutive 6 with `tripleSixForfeit`; the turn was forfeited and
  /// the roll discarded. With banked rolls the whole bank is wiped too, but
  /// moves already made this turn are kept.
  tripleSixForfeit,

  /// Banked rolls only: the die was added to the bank and the rolling
  /// sequence continues (it was a 6); roll again.
  banked,

  /// Banked rolls only: the die ended the rolling sequence but the bank can
  /// no longer be spent in full. The turn's moves were reverted to the
  /// snapshot, the bank cleared and the turn passed.
  bankDeadEnd,
}

/// Result of `Engine.roll`.
class RollResult {
  const RollResult(this.state, this.value, this.outcome);

  /// State after the roll. Contains the pending die (or, with banked rolls,
  /// the bank in the moving phase) for [RollOutcome.awaitingMove]; after
  /// [RollOutcome.banked] it is still the rolling phase; otherwise the turn
  /// has already passed.
  final GameState state;

  /// The face that was rolled (also for forfeited / unplayable rolls, so the
  /// UI can animate it).
  final int value;

  final RollOutcome outcome;
}

/// The pure rules engine: the single source of truth for game state.
///
/// Every function is deterministic and side-effect free; states are
/// immutable. This library must never depend on Flutter.
abstract final class Engine {
  // ---- Setup --------------------------------------------------------------

  /// Creates a fresh match.
  ///
  /// [activeSeats] are the participating seats (2..4 of `0..3`); team play
  /// (`rules.teamsEnabled`) needs all four. The first active seat starts.
  static GameState newGame({
    required int seed,
    RulesConfig rules = const RulesConfig(),
    List<int> activeSeats = const [0, 1, 2, 3],
  }) {
    final seats = [...activeSeats]..sort();
    if (seats.length < 2 || seats.length > seatCount) {
      throw ArgumentError.value(
          activeSeats, 'activeSeats', 'need 2 to 4 seats');
    }
    if (seats.toSet().length != seats.length ||
        seats.any((s) => s < 0 || s >= seatCount)) {
      throw ArgumentError.value(
        activeSeats,
        'activeSeats',
        'seats must be unique and within 0..${seatCount - 1}',
      );
    }
    if (rules.teamsEnabled && seats.length != seatCount) {
      throw ArgumentError.value(
        activeSeats,
        'activeSeats',
        'team play needs all four seats',
      );
    }
    return GameState(
      tokens: [
        for (var s = 0; s < seatCount; s++)
          List<int>.filled(tokensPerSeat, yardPosition),
      ],
      rules: rules,
      activeSeats: seats,
      currentSeat: seats.first,
      rngState: seed,
    );
  }

  // ---- Rolling ------------------------------------------------------------

  /// Rolls the die for the current seat.
  ///
  /// Draws from the seeded PRNG, applies the triple-six forfeit and passes
  /// the turn automatically when no legal move exists.
  ///
  /// With `rules.bankedRolls` this adds the die to the bank instead; see
  /// `docs/ludo-rules.md` section 8.
  static RollResult roll(GameState state) {
    if (state.isOver) {
      throw StateError('The game is over.');
    }
    if (state.rules.bankedRolls) {
      return _rollBanked(state);
    }
    if (state.dice != null) {
      throw StateError('A roll is already pending; choose a move first.');
    }

    final drawn = Dice.roll(state.rngState);
    final value = drawn.value;
    final sixes = value == 6 ? state.consecutiveSixes + 1 : 0;

    if (state.rules.tripleSixForfeit && sixes >= 3) {
      return RollResult(
        _passTurn(state.copyWith(rngState: drawn.nextState)),
        value,
        RollOutcome.tripleSixForfeit,
      );
    }

    final rolled = state.copyWith(
      dice: value,
      consecutiveSixes: sixes,
      rngState: drawn.nextState,
    );
    if (legalMoves(rolled).isEmpty) {
      return RollResult(_passTurn(rolled), value, RollOutcome.noLegalMoves);
    }
    return RollResult(rolled, value, RollOutcome.awaitingMove);
  }

  /// Rolls (and auto-passes) until a move decision is needed or the game is
  /// over. Handy for bots, replays and tests.
  static GameState nextDecision(GameState state) {
    var current = state;
    while (!current.isOver && !current.awaitingMove) {
      current = roll(current).state;
    }
    return current;
  }

  /// Banked rolling phase: one die into the bank ("Roll All First").
  static RollResult _rollBanked(GameState state) {
    if (state.bankPhase == BankPhase.moving) {
      throw StateError('Spend the banked dice first.');
    }
    final rules = state.rules;
    final drawn = Dice.roll(state.rngState);
    final value = drawn.value;

    // A 6 keeps the sequence going; anything else (or a 6 without
    // extraTurnOnSix) ends it. The counter is per sequence: it is 0 at the
    // start of the turn and of every bonus sequence.
    final continues = value == 6 && rules.extraTurnOnSix;
    final sixes = continues ? state.consecutiveSixes + 1 : 0;

    if (rules.tripleSixForfeit && continues && sixes >= 3) {
      // Wipes the ENTIRE bank (_passTurn clears it); board moves stay.
      return RollResult(
        _passTurn(state.copyWith(rngState: drawn.nextState)),
        value,
        RollOutcome.tripleSixForfeit,
      );
    }

    final bank = [...state.bank, value];
    if (continues) {
      return RollResult(
        state.copyWith(
          bank: bank,
          consecutiveSixes: sixes,
          rngState: drawn.nextState,
        ),
        value,
        RollOutcome.banked,
      );
    }

    final snapshot = state.turnSnapshot ??
        TurnSnapshot(
          tokens: state.tokens,
          finishOrder: state.finishOrder,
          bank: bank,
        );
    final moving = state.copyWith(
      bank: bank,
      bankPhase: BankPhase.moving,
      consecutiveSixes: 0,
      rngState: drawn.nextState,
      turnSnapshot: snapshot,
    );
    if (legalMoves(moving).isEmpty) {
      // Dead end: undo this turn's moves, drop the bank, pass the turn.
      final reverted = moving.copyWith(
        tokens: snapshot.tokens,
        finishOrder: snapshot.finishOrder,
      );
      return RollResult(
        _passTurn(reverted),
        value,
        RollOutcome.bankDeadEnd,
      );
    }
    return RollResult(moving, value, RollOutcome.awaitingMove);
  }

  // ---- Legal moves --------------------------------------------------------

  /// All legal moves for the controlled seat with the given [dice] (defaults
  /// to the pending die in [state]).
  ///
  /// With `rules.bankedRolls` and no explicit [dice], returns the moves of the
  /// banked moving phase: one per token and distinct banked value, each
  /// carrying `Move.dieIndex`, and only moves after which the rest of the
  /// bank can still be spent in full.
  static List<Move> legalMoves(GameState state, [int? dice]) {
    if (state.rules.bankedRolls && dice == null) {
      return _legalBanked(state);
    }
    final d = dice ?? state.dice;
    if (d == null) {
      throw StateError('No die value: roll first or pass dice explicitly.');
    }
    if (d < 1 || d > 6) {
      throw ArgumentError.value(d, 'dice', 'must be 1..6');
    }
    if (state.isOver) {
      return const [];
    }
    return _movesFor(state, d);
  }

  /// Single-die moves for the controlled seat, ignoring the bank.
  static List<Move> _movesFor(GameState state, int d) {
    final owner = state.controlledSeat;
    final blockades = state.rules.blockades ? _blockadeMap(state) : null;
    final moves = <Move>[];
    for (var i = 0; i < tokensPerSeat; i++) {
      final from = state.tokens[owner][i];
      final to = _destination(state.rules, from, d);
      if (to == null) {
        continue;
      }
      if (blockades != null && !_pathClear(state, blockades, owner, from, to)) {
        continue;
      }
      moves.add(Move(owner: owner, tokenIndex: i, from: from, to: to));
    }
    return moves;
  }

  static List<Move> _legalBanked(GameState state) {
    if (state.isOver ||
        state.bankPhase != BankPhase.moving ||
        state.bank.isEmpty) {
      return const [];
    }
    final memo = <String, bool>{};
    final moves = <Move>[];
    final seen = <int>{};
    for (var index = 0; index < state.bank.length; index++) {
      final value = state.bank[index];
      if (!seen.add(value)) {
        continue; // equal dice are interchangeable
      }
      final rest = [...state.bank]..removeAt(index);
      for (final m in _movesFor(state, value)) {
        final next = state.copyWith(tokens: _effects(state, m).tokens);
        if (_canSpendAll(next, rest, memo)) {
          moves.add(Move(
            owner: m.owner,
            tokenIndex: m.tokenIndex,
            from: m.from,
            to: m.to,
            dieIndex: index,
          ));
        }
      }
    }
    return moves;
  }

  /// Whether every die in [remaining] can still be spent, in some order on
  /// some tokens, starting from the board of [state]. Bonus dice are random,
  /// so they are not considered. A move that ends the match is only fine as
  /// the very last spend.
  static bool _canSpendAll(
    GameState state,
    List<int> remaining,
    Map<String, bool> memo,
  ) {
    if (remaining.isEmpty) {
      return true;
    }
    if (state.isOver) {
      return false;
    }
    final sorted = [...remaining]..sort();
    final key = '${state.tokens.expand((t) => t).join(',')}|${sorted.join()}';
    final cached = memo[key];
    if (cached != null) {
      return cached;
    }
    var result = false;
    for (final value in sorted.toSet()) {
      final rest = [...sorted]..remove(value);
      for (final m in _movesFor(state, value)) {
        final next = state.copyWith(tokens: _effects(state, m).tokens);
        if (_canSpendAll(next, rest, memo)) {
          result = true;
          break;
        }
      }
      if (result) {
        break;
      }
    }
    memo[key] = result;
    return result;
  }

  static int? _destination(RulesConfig rules, int from, int d) {
    if (from == finishPosition) {
      return null;
    }
    if (from == yardPosition) {
      return (!rules.needSixToLeave || d == 6) ? startPosition : null;
    }
    final to = from + d;
    if (to > finishPosition) {
      return rules.exactRollToFinish ? null : finishPosition;
    }
    return to;
  }

  /// Absolute square -> seat that holds a blockade there (2+ own tokens).
  static Map<int, int> _blockadeMap(GameState state) {
    final result = <int, int>{};
    for (final seat in state.activeSeats) {
      final counts = <int, int>{};
      for (final position in state.tokens[seat]) {
        if (isOnTrack(position)) {
          final square = absoluteSquare(seat, position);
          counts[square] = (counts[square] ?? 0) + 1;
        }
      }
      counts.forEach((square, count) {
        if (count >= 2) {
          result[square] = seat;
        }
      });
    }
    return result;
  }

  static bool _pathClear(
    GameState state,
    Map<int, int> blockades,
    int owner,
    int from,
    int to,
  ) {
    if (blockades.isEmpty) {
      return true;
    }
    final first = from == yardPosition ? startPosition : from + 1;
    final last = to > lastTrackPosition ? lastTrackPosition : to;
    for (var position = first; position <= last; position++) {
      final square = absoluteSquare(owner, position);
      final blocker = blockades[square];
      if (blocker == null) {
        continue;
      }
      if (state.unitOf(blocker) != state.unitOf(owner)) {
        return false; // opponents can neither pass nor land
      }
      if (blocker != owner && position == to && !isSafeSquare(square)) {
        return false; // a teammate may pass, but not land on the block
      }
    }
    return true;
  }

  // ---- Applying moves -----------------------------------------------------

  /// Applies [move] for the pending die and returns the successor state,
  /// including captures, bonus turns, finishing and turn passing.
  ///
  /// With `rules.bankedRolls` the move spends the banked die at
  /// `move.dieIndex` (any index holding an equal value works). A capture or a
  /// token reaching home then returns the state in the rolling phase: the
  /// bonus sequence is rolled with `Engine.roll` before the next spend, and
  /// its dice are added to the remaining bank.
  ///
  /// Throws [IllegalMoveException] if the move is not currently legal. The
  /// engine recomputes the move itself, so forged `from`/`to` values are
  /// ignored.
  static GameState apply(GameState state, Move move) {
    if (state.rules.bankedRolls) {
      return _applyBanked(state, move);
    }
    final dice = state.dice;
    if (state.isOver) {
      throw const IllegalMoveException('The game is over.');
    }
    if (dice == null) {
      throw const IllegalMoveException('No roll is pending.');
    }
    final legal = legalMoves(state).where(
      (m) => m.owner == move.owner && m.tokenIndex == move.tokenIndex,
    );
    if (legal.isEmpty) {
      throw IllegalMoveException('$move is not legal with a $dice.');
    }
    final chosen = legal.first;
    final owner = chosen.owner;

    final effects = _effects(state, chosen);
    var after = state.copyWith(tokens: effects.tokens, clearDice: true);
    after = _recordFinish(after, owner);
    if (after.isOver) {
      return after.copyWith(consecutiveSixes: 0);
    }

    final rules = after.rules;
    final bonus = (dice == 6 && rules.extraTurnOnSix) ||
        (effects.captured && rules.extraTurnOnCapture) ||
        (effects.reachedHome && rules.extraTurnOnHome);
    if (bonus && after.isSeatInPlay(after.currentSeat)) {
      return after;
    }
    return _passTurn(after);
  }

  static GameState _applyBanked(GameState state, Move move) {
    if (state.isOver) {
      throw const IllegalMoveException('The game is over.');
    }
    if (state.bankPhase != BankPhase.moving || state.bank.isEmpty) {
      throw const IllegalMoveException('No banked dice are ready to spend.');
    }
    if (move.dieIndex < 0 || move.dieIndex >= state.bank.length) {
      throw IllegalMoveException('$move names a die outside the bank.');
    }
    final value = state.bank[move.dieIndex];
    final legal = legalMoves(state).where(
      (m) =>
          m.owner == move.owner &&
          m.tokenIndex == move.tokenIndex &&
          state.bank[m.dieIndex] == value,
    );
    if (legal.isEmpty) {
      throw IllegalMoveException(
        '$move is not legal with the bank ${state.bank}.',
      );
    }
    final chosen = legal.first;
    final owner = chosen.owner;
    final rest = [...state.bank]..removeAt(chosen.dieIndex);

    final effects = _effects(state, chosen);
    var after = state.copyWith(tokens: effects.tokens, bank: rest);
    after = _recordFinish(after, owner);
    if (after.isOver) {
      // Legal only as the last die, so the bank is already empty.
      return after.copyWith(
        consecutiveSixes: 0,
        bank: const [],
        bankPhase: BankPhase.rolling,
        clearSnapshot: true,
      );
    }

    final rules = after.rules;
    final bonus = (effects.captured && rules.extraTurnOnCapture) ||
        (effects.reachedHome && rules.extraTurnOnHome);
    if (bonus && after.isSeatInPlay(after.currentSeat)) {
      // Every capture / home move earns its own bonus sequence (counter 0).
      return after.copyWith(bankPhase: BankPhase.rolling, consecutiveSixes: 0);
    }
    if (rest.isEmpty) {
      return _passTurn(after);
    }
    return after;
  }

  /// Token positions after [chosen], plus what the move did.
  static ({List<List<int>> tokens, bool captured, bool reachedHome}) _effects(
    GameState state,
    Move chosen,
  ) {
    final owner = chosen.owner;
    final tokens = [
      for (final seat in state.tokens) [...seat]
    ];
    tokens[owner][chosen.tokenIndex] = chosen.to;

    var captured = false;
    if (isOnTrack(chosen.to)) {
      final square = absoluteSquare(owner, chosen.to);
      if (!isSafeSquare(square)) {
        for (final seat in state.activeSeats) {
          if (state.unitOf(seat) == state.unitOf(owner)) {
            continue;
          }
          for (var i = 0; i < tokensPerSeat; i++) {
            final position = tokens[seat][i];
            if (isOnTrack(position) &&
                absoluteSquare(seat, position) == square) {
              tokens[seat][i] = yardPosition;
              captured = true;
            }
          }
        }
      }
    }
    return (
      tokens: tokens,
      captured: captured,
      reachedHome: chosen.to == finishPosition,
    );
  }

  /// Appends [owner] to `finishOrder` when it just finished and, when that
  /// ends the match, completes the ranking.
  static GameState _recordFinish(GameState after, int owner) {
    var finishOrder = after.finishOrder;
    if (after.seatFinished(owner) && !finishOrder.contains(owner)) {
      finishOrder = [...finishOrder, owner];
      after = after.copyWith(finishOrder: finishOrder);
    }
    if (after.isOver && after.rules.endMode == EndMode.fullRanking) {
      final rest = [
        for (final seat in after.activeSeats)
          if (!finishOrder.contains(seat)) seat,
      ];
      after = after.copyWith(finishOrder: [...finishOrder, ...rest]);
    }
    return after;
  }

  // ---- Move log -----------------------------------------------------------

  /// The log entry describing [move] made in [state].
  static MoveLogEntry logEntry(GameState state, Move move) {
    final int? dice;
    if (state.rules.bankedRolls) {
      dice = move.dieIndex >= 0 && move.dieIndex < state.bank.length
          ? state.bank[move.dieIndex]
          : null;
    } else {
      dice = state.dice;
    }
    if (dice == null) {
      throw StateError('No roll is pending.');
    }
    return MoveLogEntry(
      seat: state.currentSeat,
      dice: dice,
      tokenIndex: move.tokenIndex,
    );
  }

  /// Applies a logged decision. If no roll is pending yet, rolls first (and
  /// auto-passes) exactly as the original game did.
  ///
  /// Throws [IllegalMoveException] if the entry does not match the state.
  static GameState applyEntry(GameState state, MoveLogEntry entry) {
    final ready = state.awaitingMove ? state : nextDecision(state);
    if (ready.isOver) {
      throw const IllegalMoveException('The game is over.');
    }
    if (ready.rules.bankedRolls) {
      if (entry.seat != ready.currentSeat || !ready.bank.contains(entry.dice)) {
        throw IllegalMoveException(
          '$entry does not match seat ${ready.currentSeat} '
          'with the bank ${ready.bank}.',
        );
      }
      final moves = legalMoves(ready).where(
        (m) =>
            m.tokenIndex == entry.tokenIndex &&
            ready.bank[m.dieIndex] == entry.dice,
      );
      if (moves.isEmpty) {
        throw IllegalMoveException('$entry is not a legal move.');
      }
      return apply(ready, moves.first);
    }
    if (entry.seat != ready.currentSeat || entry.dice != ready.dice) {
      throw IllegalMoveException(
        '$entry does not match seat ${ready.currentSeat} '
        'with a ${ready.dice}.',
      );
    }
    final moves =
        legalMoves(ready).where((m) => m.tokenIndex == entry.tokenIndex);
    if (moves.isEmpty) {
      throw IllegalMoveException('$entry is not a legal move.');
    }
    return apply(ready, moves.first);
  }

  /// Rebuilds a match from `seed + moveLog`.
  static GameState replay({
    required int seed,
    required List<MoveLogEntry> log,
    RulesConfig rules = const RulesConfig(),
    List<int> activeSeats = const [0, 1, 2, 3],
  }) {
    var state = newGame(seed: seed, rules: rules, activeSeats: activeSeats);
    for (final entry in log) {
      state = applyEntry(state, entry);
    }
    return state;
  }

  // ---- Turn passing -------------------------------------------------------

  static GameState _passTurn(GameState state) {
    var next = state.currentSeat;
    for (var step = 1; step <= seatCount; step++) {
      final candidate = (state.currentSeat + step) % seatCount;
      if (state.isSeatInPlay(candidate)) {
        next = candidate;
        break;
      }
    }
    return state.copyWith(
      currentSeat: next,
      clearDice: true,
      consecutiveSixes: 0,
      turnNumber: state.turnNumber + 1,
      bank: const [],
      bankPhase: BankPhase.rolling,
      clearSnapshot: true,
    );
  }
}
