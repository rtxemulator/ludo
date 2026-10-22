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
          rest: state.rest,
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
        rest: snapshot.rest,
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
    final rules = state.rules;
    final blockades = rules.blockades ? _blockadeMap(state) : null;
    // Unbreakable blockades: their tokens only move as a unit.
    final glued = rules.blockadeUnbreakableActive
        ? _pairedTokens(state, owner)
        : const <int>{};
    final moves = <Move>[];
    for (var i = 0; i < tokensPerSeat; i++) {
      if (state.isWaiting(owner, i) || glued.contains(i)) {
        continue;
      }
      final from = state.tokens[owner][i];
      final to = _destination(rules, from, d);
      if (to == null) {
        continue;
      }
      if (blockades != null && !_pathClear(state, blockades, owner, from, to)) {
        continue;
      }
      moves.add(Move(owner: owner, tokenIndex: i, from: from, to: to));
    }
    if (blockades != null && rules.blockadeMovementActive && d.isEven) {
      moves.addAll(_unitMoves(state, blockades, owner, d ~/ 2));
    }
    return moves;
  }

  /// Indices of [owner]'s tokens standing as exactly two on a non-safe track
  /// square (a blockade that may not be split).
  static Set<int> _pairedTokens(GameState state, int owner) {
    final tokens = state.tokens[owner];
    final result = <int>{};
    for (var i = 0; i < tokensPerSeat; i++) {
      final p = tokens[i];
      if (!isOnTrack(p) || isSafeSquare(absoluteSquare(owner, p))) {
        continue;
      }
      if (tokens.where((q) => q == p).length == 2) {
        result.add(i);
      }
    }
    return result;
  }

  /// Moves of two-piece blockades of [owner] as a unit, each token advancing
  /// [step] squares. The unit jumps over everything on the way; it may only
  /// land where [_unitMayLand] allows.
  static List<Move> _unitMoves(
    GameState state,
    Map<int, List<int>> blockades,
    int owner,
    int step,
  ) {
    final rules = state.rules;
    final tokens = state.tokens[owner];
    final moves = <Move>[];
    for (var i = 0; i < tokensPerSeat; i++) {
      for (var j = i + 1; j < tokensPerSeat; j++) {
        final p = tokens[i];
        if (p != tokens[j] ||
            !isOnTrack(p) ||
            state.isWaiting(owner, i) ||
            state.isWaiting(owner, j) ||
            tokens.where((q) => q == p).length != 2) {
          continue;
        }
        final holders = blockades[absoluteSquare(owner, p)];
        if (holders == null || !holders.contains(owner)) {
          continue; // not a blockade (e.g. open safe squares)
        }
        final to = _destination(rules, p, step);
        if (to == null || !_unitMayLand(state, blockades, owner, to)) {
          continue;
        }
        moves.add(
          Move(
            owner: owner,
            tokenIndex: i,
            from: p,
            to: to,
            partnerIndex: j,
          ),
        );
      }
    }
    return moves;
  }

  /// How many tokens of [seat] stand on absolute [square].
  static int _countAt(GameState state, int seat, int square) {
    var count = 0;
    for (final position in state.tokens[seat]) {
      if (isOnTrack(position) && absoluteSquare(seat, position) == square) {
        count++;
      }
    }
    return count;
  }

  /// Whether a moving blockade of [owner] may stop at relative [to].
  static bool _unitMayLand(
    GameState state,
    Map<int, List<int>> blockades,
    int owner,
    int to,
  ) {
    if (!isOnTrack(to)) {
      return true; // home column and finish hold no blockades
    }
    final square = absoluteSquare(owner, to);
    if (!isSafeSquare(square)) {
      // A moving blockade never captures a single piece, so it cannot land
      // on one.
      for (final seat in state.activeSeats) {
        if (state.unitOf(seat) != state.unitOf(owner) &&
            _countAt(state, seat, square) == 1) {
          return false;
        }
      }
    }
    final holders = blockades[square];
    if (holders == null) {
      return true;
    }
    for (final b in holders) {
      if (b == owner) {
        return false; // never on top of another pair of its own
      }
      if (state.unitOf(b) == state.unitOf(owner)) {
        if (!isSafeSquare(square)) {
          return false; // a teammate's blockade, as for a single token
        }
      } else if (!(state.rules.blockadeCaptureActive &&
          !isSafeSquare(square))) {
        return false; // opponent blockades fall only to a blockade capture
      }
    }
    return true;
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
        final next = _board(state, m);
        if (_canSpendAll(next, rest, memo)) {
          moves.add(Move(
            owner: m.owner,
            tokenIndex: m.tokenIndex,
            from: m.from,
            to: m.to,
            dieIndex: index,
            partnerIndex: m.partnerIndex,
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
    final key = '${state.tokens.expand((t) => t).join(',')}'
        '|${state.rest.expand((t) => t).join()}|${sorted.join()}';
    final cached = memo[key];
    if (cached != null) {
      return cached;
    }
    var result = false;
    for (final value in sorted.toSet()) {
      final rest = [...sorted]..remove(value);
      for (final m in _movesFor(state, value)) {
        final next = _board(state, m);
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

  /// Absolute square -> seats that hold a blockade there (2+ of their own
  /// tokens). Safe squares never hold blockades (they stay open to everyone),
  /// with one exception: a seat's own start square, where a pair that came
  /// out of the yard does form a blockade.
  static Map<int, List<int>> _blockadeMap(GameState state) {
    final result = <int, List<int>>{};
    for (final seat in state.activeSeats) {
      final counts = <int, int>{};
      for (final position in state.tokens[seat]) {
        if (isOnTrack(position)) {
          final square = absoluteSquare(seat, position);
          counts[square] = (counts[square] ?? 0) + 1;
        }
      }
      counts.forEach((square, count) {
        final open = isSafeSquare(square) &&
            square != absoluteSquare(seat, startPosition);
        if (count >= 2 && !open) {
          (result[square] ??= []).add(seat);
        }
      });
    }
    return result;
  }

  /// Whether a single token of [owner] may go from [from] to [to] without
  /// running into a blockade.
  static bool _pathClear(
    GameState state,
    Map<int, List<int>> blockades,
    int owner,
    int from,
    int to,
  ) {
    if (blockades.isEmpty) {
      return true;
    }
    final rules = state.rules;
    final first = from == yardPosition ? startPosition : from + 1;
    final last = to > lastTrackPosition ? lastTrackPosition : to;
    for (var position = first; position <= last; position++) {
      final square = absoluteSquare(owner, position);
      final holders = blockades[square];
      if (holders == null) {
        continue;
      }
      final landing = position == to;
      for (final blocker in holders) {
        if (state.unitOf(blocker) != state.unitOf(owner)) {
          if (landing && rules.pieceOnBlockadeActive) {
            continue; // a single piece may squat on an opponent blockade
          }
          return false; // opponents can neither pass nor land
        }
        if (landing) {
          if (blocker != owner && !isSafeSquare(square)) {
            return false; // a teammate may pass, but not land on the block
          }
        } else if (rules.friendlyRestrictionActive) {
          return false; // not even friendly blockades may be passed
        }
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
      (m) =>
          m.owner == move.owner &&
          m.tokenIndex == move.tokenIndex &&
          m.partnerIndex == move.partnerIndex,
    );
    if (legal.isEmpty) {
      throw IllegalMoveException('$move is not legal with a $dice.');
    }
    final chosen = legal.first;
    final owner = chosen.owner;

    final effects = _effects(state, chosen);
    var after = state.copyWith(
      tokens: effects.tokens,
      rest: effects.rest,
      clearDice: true,
    );
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
          m.partnerIndex == move.partnerIndex &&
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
    var after = state.copyWith(
      tokens: effects.tokens,
      rest: effects.rest,
      bank: rest,
    );
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

  /// [state] with [move] played on the board (tokens and waiting only).
  static GameState _board(GameState state, Move move) {
    final e = _effects(state, move);
    return state.copyWith(tokens: e.tokens, rest: e.rest);
  }

  /// Token positions and waiting counters after [chosen], plus what the move
  /// did.
  static ({
    List<List<int>> tokens,
    List<List<int>> rest,
    bool captured,
    bool reachedHome,
  }) _effects(GameState state, Move chosen) {
    final owner = chosen.owner;
    final rules = state.rules;
    final tokens = [
      for (final seat in state.tokens) [...seat]
    ];
    final rest = [
      for (final seat in state.rest) [...seat]
    ];
    tokens[owner][chosen.tokenIndex] = chosen.to;
    if (chosen.isUnit) {
      tokens[owner][chosen.partnerIndex] = chosen.to;
    }

    var captured = false;
    if (isOnTrack(chosen.to)) {
      final square = absoluteSquare(owner, chosen.to);
      // Opponent blockades a single piece lands on (squatting): it neither
      // captures them nor is it safe from them; it just has to wait.
      final shielded = <int>{};
      if (!chosen.isUnit && rules.pieceOnBlockadeActive) {
        final holders = _blockadeMap(state)[square] ?? const <int>[];
        for (final seat in holders) {
          if (state.unitOf(seat) != state.unitOf(owner)) {
            shielded.add(seat);
          }
        }
        if (shielded.isNotEmpty) {
          rest[owner][chosen.tokenIndex] = 1;
        }
      }
      if (!isSafeSquare(square)) {
        for (final seat in state.activeSeats) {
          if (state.unitOf(seat) == state.unitOf(owner) ||
              shielded.contains(seat)) {
            continue;
          }
          // A moving blockade only ever captures blockades, never a single
          // piece (such a landing is not legal in the first place).
          if (chosen.isUnit && _countAt(state, seat, square) < 2) {
            continue;
          }
          for (var i = 0; i < tokensPerSeat; i++) {
            final position = tokens[seat][i];
            if (isOnTrack(position) &&
                absoluteSquare(seat, position) == square) {
              tokens[seat][i] = yardPosition;
              rest[seat][i] = 0;
              captured = true;
            }
          }
        }
      }
    }
    return (
      tokens: tokens,
      rest: rest,
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
      unit: move.isUnit,
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
            m.isUnit == entry.unit &&
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
    final moves = legalMoves(ready).where(
      (m) => m.tokenIndex == entry.tokenIndex && m.isUnit == entry.unit,
    );
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
    // A turn of the controlled seat ends: its waiting tokens wait one less.
    final waiting = state.rest[state.controlledSeat];
    final rest = waiting.any((r) => r > 0)
        ? [
            for (var seat = 0; seat < seatCount; seat++)
              if (seat == state.controlledSeat)
                [for (final r in waiting) r > 0 ? r - 1 : 0]
              else
                state.rest[seat],
          ]
        : null;
    return state.copyWith(
      rest: rest,
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
