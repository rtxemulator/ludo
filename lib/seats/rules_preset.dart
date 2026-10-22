import 'package:ludo/engine/ludo_engine.dart';

/// The named rule sets of `docs/ludo-rules.md` section 7.
enum RulesPreset {
  classic('Classic'),
  quick('Quick'),
  strategic('Strategic'),

  /// Any other combination of house rules.
  custom('Custom');

  const RulesPreset(this.label);

  final String label;

  /// The three real presets (everything but [custom]).
  static const List<RulesPreset> named = [classic, quick, strategic];

  /// The rules of this preset. [custom] has no rules of its own: it returns
  /// the classic ones.
  RulesConfig get rules => switch (this) {
        RulesPreset.classic => const RulesConfig.classic(),
        RulesPreset.quick => const RulesConfig.quick(),
        RulesPreset.strategic => const RulesConfig.strategic(),
        RulesPreset.custom => const RulesConfig.classic(),
      };

  /// Which preset [rules] is.
  ///
  /// `teamsEnabled` (derived from the seats), `teammateControl` and
  /// `bankedRolls` (table options, not part of the presets) are ignored.
  static RulesPreset of(RulesConfig rules) {
    final base = _normalise(rules);
    for (final preset in named) {
      if (_normalise(preset.rules) == base) {
        return preset;
      }
    }
    return custom;
  }

  /// [current] with this preset's switches applied; the table options
  /// (`teammateControl`, `bankedRolls`) and `teamsEnabled` stay as they are.
  RulesConfig applyTo(RulesConfig current) {
    return rules.copyWith(
      teammateControl: current.teammateControl,
      bankedRolls: current.bankedRolls,
      teamsEnabled: current.teamsEnabled,
    );
  }

  static RulesConfig _normalise(RulesConfig rules) => rules.copyWith(
        teamsEnabled: false,
        teammateControl: true,
        bankedRolls: false,
      );
}

/// JSON form of [RulesConfig] (the engine itself stays free of
/// serialisation). Used by `MatchSetup.toJson` and later by the saves.
Map<String, Object?> rulesToJson(RulesConfig rules) => {
      'endMode': rules.endMode.name,
      'teammateControl': rules.teammateControl,
      'needSixToLeave': rules.needSixToLeave,
      'extraTurnOnSix': rules.extraTurnOnSix,
      'tripleSixForfeit': rules.tripleSixForfeit,
      'extraTurnOnCapture': rules.extraTurnOnCapture,
      'extraTurnOnHome': rules.extraTurnOnHome,
      'exactRollToFinish': rules.exactRollToFinish,
      'blockades': rules.blockades,
      'teamsEnabled': rules.teamsEnabled,
      'bankedRolls': rules.bankedRolls,
      'blockadeFriendlyRestriction': rules.blockadeFriendlyRestriction,
      'blockadeMovement': rules.blockadeMovement,
      'blockadeCapture': rules.blockadeCapture,
      'blockadeUnbreakable': rules.blockadeUnbreakable,
      'pieceOnBlockade': rules.pieceOnBlockade,
    };

/// Reads rules written by [rulesToJson]; missing keys keep their defaults.
RulesConfig rulesFromJson(Map<String, Object?> json) {
  const d = RulesConfig();
  bool flag(String key, bool fallback) {
    final v = json[key];
    return v is bool ? v : fallback;
  }

  var endMode = d.endMode;
  for (final mode in EndMode.values) {
    if (mode.name == json['endMode']) {
      endMode = mode;
    }
  }
  return RulesConfig(
    endMode: endMode,
    teammateControl: flag('teammateControl', d.teammateControl),
    needSixToLeave: flag('needSixToLeave', d.needSixToLeave),
    extraTurnOnSix: flag('extraTurnOnSix', d.extraTurnOnSix),
    tripleSixForfeit: flag('tripleSixForfeit', d.tripleSixForfeit),
    extraTurnOnCapture: flag('extraTurnOnCapture', d.extraTurnOnCapture),
    extraTurnOnHome: flag('extraTurnOnHome', d.extraTurnOnHome),
    exactRollToFinish: flag('exactRollToFinish', d.exactRollToFinish),
    blockades: flag('blockades', d.blockades),
    teamsEnabled: flag('teamsEnabled', d.teamsEnabled),
    bankedRolls: flag('bankedRolls', d.bankedRolls),
    blockadeFriendlyRestriction:
        flag('blockadeFriendlyRestriction', d.blockadeFriendlyRestriction),
    blockadeMovement: flag('blockadeMovement', d.blockadeMovement),
    blockadeCapture: flag('blockadeCapture', d.blockadeCapture),
    blockadeUnbreakable: flag('blockadeUnbreakable', d.blockadeUnbreakable),
    pieceOnBlockade: flag('pieceOnBlockade', d.pieceOnBlockade),
  );
}
