/// A single token move chosen from `Engine.legalMoves`.
class Move {
  const Move({
    required this.owner,
    required this.tokenIndex,
    required this.from,
    required this.to,
    this.dieIndex = 0,
    this.partnerIndex = -1,
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

  /// The second token of a moving blockade (`RulesConfig.blockadeMovement`):
  /// both tokens advance together, [tokenIndex] being the lower index. `-1`
  /// for an ordinary single-token move.
  final int partnerIndex;

  /// Whether this moves a two-piece blockade as a unit.
  bool get isUnit => partnerIndex >= 0;

  /// Whether this move moves token [index] of its owner.
  bool moves(int index) => tokenIndex == index || partnerIndex == index;

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.owner == owner &&
      other.tokenIndex == tokenIndex &&
      other.from == from &&
      other.to == to &&
      other.dieIndex == dieIndex &&
      other.partnerIndex == partnerIndex;

  @override
  int get hashCode =>
      Object.hash(owner, tokenIndex, from, to, dieIndex, partnerIndex);

  @override
  String toString() => 'Move(seat $owner token $tokenIndex'
      '${isUnit ? '+$partnerIndex' : ''}: $from -> $to'
      '${dieIndex == 0 ? '' : ', die #$dieIndex'})';
}

/// One decision in the move log: `(seat, dice, tokenIndex)`, plus [unit] when
/// a blockade moved as one.
///
/// [seat] is the seat whose turn it was (the roller). Rolls that produced no
/// decision (forfeits, no legal move) are not logged: they are reproduced
/// deterministically from the seed.
class MoveLogEntry {
  const MoveLogEntry({
    required this.seat,
    required this.dice,
    required this.tokenIndex,
    this.unit = false,
  });

  final int seat;
  final int dice;

  /// The moved token; the lower index of the pair for a [unit] move.
  final int tokenIndex;

  /// A two-piece blockade moved as a unit (`RulesConfig.blockadeMovement`).
  final bool unit;

  @override
  bool operator ==(Object other) =>
      other is MoveLogEntry &&
      other.seat == seat &&
      other.dice == dice &&
      other.tokenIndex == tokenIndex &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(seat, dice, tokenIndex, unit);

  @override
  String toString() =>
      'MoveLogEntry($seat, $dice, $tokenIndex${unit ? ', unit' : ''})';
}
