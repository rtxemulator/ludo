/// How a match ends.
enum EndMode {
  /// The match ends the instant the first player (or team) gets every token
  /// home.
  firstToWin,

  /// The match continues until only one player (or team) remains, which
  /// establishes a full 1st..Nth ranking.
  fullRanking,
}

/// Immutable switchboard of every configurable house rule.
///
/// See `docs/ludo-rules.md` for the definitive description of each switch.
class RulesConfig {
  const RulesConfig({
    this.endMode = EndMode.fullRanking,
    this.teammateControl = true,
    this.needSixToLeave = true,
    this.extraTurnOnSix = true,
    this.tripleSixForfeit = true,
    this.extraTurnOnCapture = true,
    this.extraTurnOnHome = true,
    this.exactRollToFinish = true,
    this.blockades = false,
    this.teamsEnabled = false,
    this.bankedRolls = false,
    this.blockadeFormFromSafe = true,
    this.blockadeFriendlyRestriction = false,
    this.blockadeMovement = false,
    this.blockadeCapture = false,
    this.blockadeUnbreakable = false,
    this.pieceOnBlockade = false,
  });

  /// Balanced, standard tournament rules (all defaults).
  const RulesConfig.classic() : this();

  /// Fast casual sessions: tokens leave on any roll, no triple-six forfeit,
  /// first player home wins.
  const RulesConfig.quick()
      : this(
          needSixToLeave: false,
          tripleSixForfeit: false,
          endMode: EndMode.firstToWin,
        );

  /// Tactical play: blockades on, captures do not grant an extra turn.
  const RulesConfig.strategic()
      : this(blockades: true, extraTurnOnCapture: false);

  /// Game termination mode.
  final EndMode endMode;

  /// A finished player keeps rolling and moves their partner's tokens
  /// (2v2 only).
  final bool teammateControl;

  /// A 6 is required to bring a token out of the yard.
  final bool needSixToLeave;

  /// Rolling a 6 grants a bonus turn.
  final bool extraTurnOnSix;

  /// Rolling three consecutive 6s forfeits the turn.
  final bool tripleSixForfeit;

  /// Capturing an opponent grants a bonus turn.
  final bool extraTurnOnCapture;

  /// Reaching the finish square grants a bonus turn.
  final bool extraTurnOnHome;

  /// A token must hit the finish square exactly.
  final bool exactRollToFinish;

  /// Two or more friendly tokens on one square form an impassable block.
  final bool blockades;

  /// 2v2 team play (seats 0+2 versus seats 1+3). Derived from the seat
  /// configuration by the caller.
  final bool teamsEnabled;

  /// Banked ("stacking") dice: a turn first rolls all its dice into a bank
  /// ("Roll All First"), then spends them in any order, all-or-nothing.
  /// Off by default; see `docs/ludo-rules.md` section 8.
  final bool bankedRolls;

  // ---- Blockade options ---------------------------------------------------
  //
  // All of these only matter with [blockades] ([blockadeFormFromSafe] is on by
  // default, the others off); [blockadeCapture] and
  // [blockadeUnbreakable] also need [blockadeMovement]. The engine reads the
  // `...Active` getters below, which apply those prerequisites, so a stale
  // flag can never switch a rule on by itself. See `docs/ludo-rules.md`
  // section 9.

  /// Forming blockades from a safe square: two or more of your tokens on a
  /// safe square (a yard exit or a star) may, on an even roll, step out
  /// together onto an ordinary square, each token advancing half the roll,
  /// which forms a blockade there. Safe squares themselves never hold
  /// blockades. On by default (it only matters with [blockades]).
  final bool blockadeFormFromSafe;

  /// Nobody may pass a blockade of their own or of a teammate (landing
  /// rules are unchanged).
  final bool blockadeFriendlyRestriction;

  /// A pair of tokens on one square (a two-piece blockade) can also move as a
  /// unit: only on an even roll, each token advancing half of it, jumping
  /// over any blockade on the way.
  final bool blockadeMovement;

  /// A moving blockade that lands on an opponent blockade (on a non-safe
  /// square) captures it. (A moving blockade never captures a single piece
  /// and cannot land on one.) Needs [blockadeMovement].
  final bool blockadeCapture;

  /// A two-piece blockade on a non-safe square cannot be split: its tokens
  /// only move together (so only on even rolls) until the pair stands on a
  /// safe square. Needs [blockadeMovement].
  final bool blockadeUnbreakable;

  /// A single piece may land on a square held by an opponent's blockade
  /// without capturing it. It cannot move for the rest of the turn it
  /// arrives in (it is free from its owner's next turn) and can be captured
  /// by a single token of the blockade's owner landing on the square; if the
  /// blockade moves away it stays behind.
  final bool pieceOnBlockade;

  /// Forming blockades from safe squares, in force.
  bool get formFromSafeActive => blockades && blockadeFormFromSafe;

  /// Friendly-blockade restriction, in force.
  bool get friendlyRestrictionActive =>
      blockades && blockadeFriendlyRestriction;

  /// Moving blockades, in force.
  bool get blockadeMovementActive => blockades && blockadeMovement;

  /// Blockade capture, in force.
  bool get blockadeCaptureActive => blockadeMovementActive && blockadeCapture;

  /// Unbreakable blockades, in force.
  bool get blockadeUnbreakableActive =>
      blockadeMovementActive && blockadeUnbreakable;

  /// Pieces on blockades, in force.
  bool get pieceOnBlockadeActive => blockades && pieceOnBlockade;

  /// These rules with every blockade option whose prerequisite is missing
  /// switched off (all of them without [blockades]; capture and
  /// unbreakable without [blockadeMovement]).
  RulesConfig normalized() {
    return copyWith(
      blockadeFriendlyRestriction: friendlyRestrictionActive,
      blockadeMovement: blockadeMovementActive,
      blockadeCapture: blockadeCaptureActive,
      blockadeUnbreakable: blockadeUnbreakableActive,
      pieceOnBlockade: pieceOnBlockadeActive,
    );
  }

  RulesConfig copyWith({
    EndMode? endMode,
    bool? teammateControl,
    bool? needSixToLeave,
    bool? extraTurnOnSix,
    bool? tripleSixForfeit,
    bool? extraTurnOnCapture,
    bool? extraTurnOnHome,
    bool? exactRollToFinish,
    bool? blockades,
    bool? teamsEnabled,
    bool? bankedRolls,
    bool? blockadeFormFromSafe,
    bool? blockadeFriendlyRestriction,
    bool? blockadeMovement,
    bool? blockadeCapture,
    bool? blockadeUnbreakable,
    bool? pieceOnBlockade,
  }) {
    return RulesConfig(
      endMode: endMode ?? this.endMode,
      teammateControl: teammateControl ?? this.teammateControl,
      needSixToLeave: needSixToLeave ?? this.needSixToLeave,
      extraTurnOnSix: extraTurnOnSix ?? this.extraTurnOnSix,
      tripleSixForfeit: tripleSixForfeit ?? this.tripleSixForfeit,
      extraTurnOnCapture: extraTurnOnCapture ?? this.extraTurnOnCapture,
      extraTurnOnHome: extraTurnOnHome ?? this.extraTurnOnHome,
      exactRollToFinish: exactRollToFinish ?? this.exactRollToFinish,
      blockades: blockades ?? this.blockades,
      teamsEnabled: teamsEnabled ?? this.teamsEnabled,
      bankedRolls: bankedRolls ?? this.bankedRolls,
      blockadeFormFromSafe: blockadeFormFromSafe ?? this.blockadeFormFromSafe,
      blockadeFriendlyRestriction:
          blockadeFriendlyRestriction ?? this.blockadeFriendlyRestriction,
      blockadeMovement: blockadeMovement ?? this.blockadeMovement,
      blockadeCapture: blockadeCapture ?? this.blockadeCapture,
      blockadeUnbreakable: blockadeUnbreakable ?? this.blockadeUnbreakable,
      pieceOnBlockade: pieceOnBlockade ?? this.pieceOnBlockade,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RulesConfig &&
      other.endMode == endMode &&
      other.teammateControl == teammateControl &&
      other.needSixToLeave == needSixToLeave &&
      other.extraTurnOnSix == extraTurnOnSix &&
      other.tripleSixForfeit == tripleSixForfeit &&
      other.extraTurnOnCapture == extraTurnOnCapture &&
      other.extraTurnOnHome == extraTurnOnHome &&
      other.exactRollToFinish == exactRollToFinish &&
      other.blockades == blockades &&
      other.teamsEnabled == teamsEnabled &&
      other.bankedRolls == bankedRolls &&
      other.blockadeFormFromSafe == blockadeFormFromSafe &&
      other.blockadeFriendlyRestriction == blockadeFriendlyRestriction &&
      other.blockadeMovement == blockadeMovement &&
      other.blockadeCapture == blockadeCapture &&
      other.blockadeUnbreakable == blockadeUnbreakable &&
      other.pieceOnBlockade == pieceOnBlockade;

  @override
  int get hashCode => Object.hash(
        endMode,
        teammateControl,
        needSixToLeave,
        extraTurnOnSix,
        tripleSixForfeit,
        extraTurnOnCapture,
        extraTurnOnHome,
        exactRollToFinish,
        blockades,
        teamsEnabled,
        bankedRolls,
        blockadeFormFromSafe,
        blockadeFriendlyRestriction,
        blockadeMovement,
        blockadeCapture,
        blockadeUnbreakable,
        pieceOnBlockade,
      );

  @override
  String toString() => 'RulesConfig(endMode: $endMode, '
      'teammateControl: $teammateControl, needSixToLeave: $needSixToLeave, '
      'extraTurnOnSix: $extraTurnOnSix, tripleSixForfeit: $tripleSixForfeit, '
      'extraTurnOnCapture: $extraTurnOnCapture, '
      'extraTurnOnHome: $extraTurnOnHome, '
      'exactRollToFinish: $exactRollToFinish, blockades: $blockades, '
      'teamsEnabled: $teamsEnabled, bankedRolls: $bankedRolls'
      '${blockades ? ', blockade options: ${_optionNames().join(' ')}' : ''})';

  List<String> _optionNames() => [
        if (blockadeFormFromSafe) 'formFromSafe',
        if (blockadeFriendlyRestriction) 'friendlyRestriction',
        if (blockadeMovement) 'movement',
        if (blockadeCapture) 'capture',
        if (blockadeUnbreakable) 'unbreakable',
        if (pieceOnBlockade) 'pieceOnBlockade',
      ];
}
