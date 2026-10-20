/// A single token move chosen from `Engine.legalMoves`.
class Move {
  const Move({
    required this.owner,
    required this.tokenIndex,
    required this.from,
    required this.to,
    this.dieIndex = 0,
  });

  /// Seat that owns the moved token. With teammate control this can differ
  /// from the seat whose turn it is.
  final int owner;

  /// Which of the owner's 4 tokens moves (`0..3`).
  final int tokenIndex;

  /// Relative position before the move.
  final int from;

  /// Relative position after the move.
  final int to;

  /// Index into `GameState.bank` of the die this move spends. Always `0`
  /// when `RulesConfig.bankedRolls` is off (the single pending die).
  final int dieIndex;

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.owner == owner &&
      other.tokenIndex == tokenIndex &&
      other.from == from &&
      other.to == to &&
      other.dieIndex == dieIndex;

  @override
  int get hashCode => Object.hash(owner, tokenIndex, from, to, dieIndex);

  @override
  String toString() => 'Move(seat $owner token $tokenIndex: $from -> $to'
      '${dieIndex == 0 ? '' : ', die #$dieIndex'})';
}

/// One decision in the move log: `(seat, dice, tokenIndex)`.
///
/// [seat] is the seat whose turn it was (the roller). Rolls that produced no
/// decision (forfeits, no legal move) are not logged: they are reproduced
/// deterministically from the seed.
class MoveLogEntry {
  const MoveLogEntry({
    required this.seat,
    required this.dice,
    required this.tokenIndex,
  });

  final int seat;
  final int dice;
  final int tokenIndex;

  @override
  bool operator ==(Object other) =>
      other is MoveLogEntry &&
      other.seat == seat &&
      other.dice == dice &&
      other.tokenIndex == tokenIndex;

  @override
  int get hashCode => Object.hash(seat, dice, tokenIndex);

  @override
  String toString() => 'MoveLogEntry($seat, $dice, $tokenIndex)';
}
