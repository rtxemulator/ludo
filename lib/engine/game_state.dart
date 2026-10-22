import 'board.dart';
import 'rules_config.dart';

/// Phase of a banked-dice turn (`RulesConfig.bankedRolls`).
enum BankPhase {
  /// The seat is rolling dice into the bank (also the phase between turns and
  /// during a bonus rolling sequence).
  rolling,

  /// The roll sequence ended; the bank is spent one die at a time.
  moving,
}

/// Board and bank as they were when the moving phase of a banked turn began.
///
/// A dead end (the whole bank cannot be spent) reverts the turn to this.
class TurnSnapshot {
  TurnSnapshot({
    required List<List<int>> tokens,
    required List<int> finishOrder,
    required List<int> bank,
    List<List<int>>? rest,
  })  : tokens = List.unmodifiable(tokens.map(List<int>.unmodifiable)),
        finishOrder = List.unmodifiable(finishOrder),
        bank = List.unmodifiable(bank),
        rest = List.unmodifiable(
          (rest ?? zeroRest()).map(List<int>.unmodifiable),
        );

  final List<List<int>> tokens;

  /// `GameState.rest` when the moving phase began.
  final List<List<int>> rest;
  final List<int> finishOrder;

  /// The bank when the moving phase started.
  final List<int> bank;

  @override
  bool operator ==(Object other) =>
      other is TurnSnapshot &&
      _listEquals(other.finishOrder, finishOrder) &&
      _listEquals(other.bank, bank) &&
      _tokensEqual(other.tokens, tokens) &&
      _tokensEqual(other.rest, rest);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(finishOrder),
        Object.hashAll(bank),
        Object.hashAll(tokens.expand((seat) => seat)),
        Object.hashAll(rest.expand((seat) => seat)),
      );
}

/// A fresh `rest` table: nobody is waiting.
List<List<int>> zeroRest() => [
      for (var s = 0; s < seatCount; s++) List<int>.filled(tokensPerSeat, 0),
    ];

/// Immutable snapshot of a Ludo match.
///
/// Create new matches with `Engine.newGame`; derive successors only through
/// `Engine.roll` / `Engine.apply`.
class GameState {
  GameState({
    required List<List<int>> tokens,
    required this.rules,
    required List<int> activeSeats,
    required this.currentSeat,
    required this.rngState,
    this.dice,
    this.consecutiveSixes = 0,
    this.turnNumber = 0,
    List<int> finishOrder = const [],
    List<int> bank = const [],
    this.bankPhase = BankPhase.rolling,
    this.turnSnapshot,
    List<List<int>>? rest,
  })  : tokens = List.unmodifiable(tokens.map(List<int>.unmodifiable)),
        activeSeats = List.unmodifiable(activeSeats),
        finishOrder = List.unmodifiable(finishOrder),
        bank = List.unmodifiable(bank),
        rest = List.unmodifiable(
          (rest ?? zeroRest()).map(List<int>.unmodifiable),
        );

  const GameState._trusted({
    required this.tokens,
    required this.rules,
    required this.activeSeats,
    required this.currentSeat,
    required this.rngState,
    required this.dice,
    required this.consecutiveSixes,
    required this.turnNumber,
    required this.finishOrder,
    required this.bank,
    required this.bankPhase,
    required this.turnSnapshot,
    required this.rest,
  });

  /// `tokens[seat][i]` is the relative position of token `i` of `seat`.
  final List<List<int>> tokens;

  /// `rest[seat][i]` is how many more turn ends of its controlling seat
  /// token `i` must sit out (`> 0`: it cannot move). Only a piece squatting
  /// on an opponent blockade (`RulesConfig.pieceOnBlockade`) ever waits.
  final List<List<int>> rest;

  /// Whether token [index] of [seat] is waiting and cannot move.
  bool isWaiting(int seat, int index) => rest[seat][index] > 0;

  final RulesConfig rules;

  /// Seats taking part in the match, ascending (2, 3 or 4 of `0..3`).
  final List<int> activeSeats;

  /// Seat whose turn it is.
  final int currentSeat;

  /// Pending die value awaiting a move, or `null` when a roll is due.
  final int? dice;

  /// Consecutive 6s rolled in the current turn.
  final int consecutiveSixes;

  /// PRNG state for the next roll.
  final int rngState;

  /// Increases every time the turn passes to another seat.
  final int turnNumber;

  /// Seats in the order they got all tokens home. In `fullRanking` the last
  /// unfinished seat(s) are appended automatically when the match ends.
  final List<int> finishOrder;

  /// Banked dice of the current turn, in the order rolled (empty unless
  /// `rules.bankedRolls`). Cleared whenever the turn passes, so only
  /// [currentSeat] ever holds dice; see [bankOf].
  final List<int> bank;

  /// Whether the current banked turn is still rolling or already spending.
  /// Meaningless when `rules.bankedRolls` is off.
  final BankPhase bankPhase;

  /// Board and bank when this turn's moving phase began, or `null` before it
  /// started (and when `rules.bankedRolls` is off).
  final TurnSnapshot? turnSnapshot;

  /// The banked dice held by [seat]: [bank] for the current seat, otherwise
  /// empty.
  List<int> bankOf(int seat) => seat == currentSeat ? bank : const [];

  GameState copyWith({
    List<List<int>>? tokens,
    int? currentSeat,
    int? dice,
    bool clearDice = false,
    int? consecutiveSixes,
    int? rngState,
    int? turnNumber,
    List<int>? finishOrder,
    List<int>? bank,
    BankPhase? bankPhase,
    TurnSnapshot? turnSnapshot,
    bool clearSnapshot = false,
    List<List<int>>? rest,
  }) {
    return GameState._trusted(
      tokens: tokens == null
          ? this.tokens
          : List.unmodifiable(tokens.map(List<int>.unmodifiable)),
      rules: rules,
      activeSeats: activeSeats,
      currentSeat: currentSeat ?? this.currentSeat,
      dice: clearDice ? null : (dice ?? this.dice),
      consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
      rngState: rngState ?? this.rngState,
      turnNumber: turnNumber ?? this.turnNumber,
      finishOrder: finishOrder == null
          ? this.finishOrder
          : List.unmodifiable(finishOrder),
      bank: bank == null ? this.bank : List.unmodifiable(bank),
      bankPhase: bankPhase ?? this.bankPhase,
      turnSnapshot: clearSnapshot ? null : (turnSnapshot ?? this.turnSnapshot),
      rest: rest == null
          ? this.rest
          : List.unmodifiable(rest.map(List<int>.unmodifiable)),
    );
  }

  // ---- Seats, teams and units --------------------------------------------

  bool isActive(int seat) => activeSeats.contains(seat);

  /// The competing unit of [seat]: the team (`seat % 2`) in 2v2 play,
  /// otherwise the seat itself.
  int unitOf(int seat) => rules.teamsEnabled ? seat % 2 : seat;

  /// Distinct competing units, in seat order.
  List<int> get units => [
        ...{for (final seat in activeSeats) unitOf(seat)},
      ];

  /// Active seats belonging to [unit].
  List<int> seatsOfUnit(int unit) => [
        for (final seat in activeSeats)
          if (unitOf(seat) == unit) seat,
      ];

  /// Whether all 4 tokens of [seat] are home.
  bool seatFinished(int seat) =>
      isActive(seat) && tokens[seat].every((p) => p == finishPosition);

  /// Whether every seat of [unit] has finished.
  bool unitFinished(int unit) {
    final seats = seatsOfUnit(unit);
    return seats.isNotEmpty && seats.every(seatFinished);
  }

  // ---- Turn flow ----------------------------------------------------------

  /// Whether the match has ended.
  bool get isOver {
    var unfinished = 0;
    var anyFinished = false;
    for (final unit in units) {
      if (unitFinished(unit)) {
        anyFinished = true;
      } else {
        unfinished++;
      }
    }
    return rules.endMode == EndMode.firstToWin ? anyFinished : unfinished <= 1;
  }

  /// Whether a die roll is due (with banked rolls: the seat is in the rolling
  /// phase of its turn or of a bonus sequence).
  bool get awaitingRoll => rules.bankedRolls
      ? bankPhase == BankPhase.rolling && !isOver
      : dice == null && !isOver;

  /// Whether a move decision is due: a pending die, or (banked rolls) the
  /// moving phase with dice left to spend.
  bool get awaitingMove => rules.bankedRolls
      ? bankPhase == BankPhase.moving && bank.isNotEmpty && !isOver
      : dice != null && !isOver;

  /// Seat whose tokens move on this turn. Normally [currentSeat]; with
  /// teammate control a finished player moves their partner's tokens.
  int get controlledSeat {
    final seat = currentSeat;
    if (rules.teamsEnabled && rules.teammateControl && seatFinished(seat)) {
      final partner = partnerOf(seat);
      if (isActive(partner) && !seatFinished(partner)) {
        return partner;
      }
    }
    return seat;
  }

  /// Whether [seat] still takes turns (is not skipped in the rotation).
  bool isSeatInPlay(int seat) {
    if (!isActive(seat)) {
      return false;
    }
    if (!seatFinished(seat)) {
      return true;
    }
    if (!rules.teamsEnabled || !rules.teammateControl) {
      return false;
    }
    final partner = partnerOf(seat);
    return isActive(partner) && !seatFinished(partner);
  }

  // ---- Results ------------------------------------------------------------

  /// Finished players/teams, best first. Each entry lists the seats of that
  /// unit (one seat, or two partners in team play). A team is ranked at the
  /// moment its *second* partner finishes.
  List<List<int>> get ranking {
    final result = <List<int>>[];
    final seen = <int>{};
    final ranked = <int>{};
    for (final seat in finishOrder) {
      seen.add(seat);
      final unit = unitOf(seat);
      final seats = seatsOfUnit(unit);
      if (seats.every(seen.contains) && ranked.add(unit)) {
        result.add(seats);
      }
    }
    return result;
  }

  /// Seats of the winning player/team, or `null` while nobody has finished.
  List<int>? get winners {
    final r = ranking;
    return r.isEmpty ? null : r.first;
  }

  // ---- Value semantics ----------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (other is! GameState) {
      return false;
    }
    if (other.rules != rules ||
        other.currentSeat != currentSeat ||
        other.dice != dice ||
        other.consecutiveSixes != consecutiveSixes ||
        other.rngState != rngState ||
        other.turnNumber != turnNumber ||
        other.bankPhase != bankPhase ||
        other.turnSnapshot != turnSnapshot) {
      return false;
    }
    return _listEquals(other.activeSeats, activeSeats) &&
        _listEquals(other.finishOrder, finishOrder) &&
        _listEquals(other.bank, bank) &&
        _tokensEqual(other.tokens, tokens) &&
        _tokensEqual(other.rest, rest);
  }

  @override
  int get hashCode => Object.hash(
        rules,
        currentSeat,
        dice,
        consecutiveSixes,
        rngState,
        turnNumber,
        Object.hashAll(activeSeats),
        Object.hashAll(finishOrder),
        Object.hashAll(tokens.expand((seat) => seat)),
        Object.hashAll(bank),
        bankPhase,
        turnSnapshot,
        Object.hashAll(rest.expand((seat) => seat)),
      );

  @override
  String toString() => 'GameState(turn $turnNumber, seat $currentSeat, '
      'dice $dice, sixes $consecutiveSixes, tokens $tokens, '
      'finishOrder $finishOrder'
      '${rules.bankedRolls ? ', bank $bank ${bankPhase.name}' : ''})';
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _tokensEqual(List<List<int>> a, List<List<int>> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (!_listEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}
