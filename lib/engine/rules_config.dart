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
      other.bankedRolls == bankedRolls;

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
      );

  @override
  String toString() => 'RulesConfig(endMode: $endMode, '
      'teammateControl: $teammateControl, needSixToLeave: $needSixToLeave, '
      'extraTurnOnSix: $extraTurnOnSix, tripleSixForfeit: $tripleSixForfeit, '
      'extraTurnOnCapture: $extraTurnOnCapture, '
      'extraTurnOnHome: $extraTurnOnHome, '
      'exactRollToFinish: $exactRollToFinish, blockades: $blockades, '
      'teamsEnabled: $teamsEnabled, bankedRolls: $bankedRolls)';
}
