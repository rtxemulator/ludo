import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';

final DateTime t0 = DateTime.utc(2026, 10, 26, 14, 5);

/// One finished (or capped) random game, autosaved the way the controller
/// will: `GameSave.begin` then `withEntry` after every decision.
class Played {
  Played({
    required this.setup,
    required this.seed,
    required this.save,
    required this.states,
    required this.rolls,
  });

  final MatchSetup setup;
  final int seed;

  /// The save after the last decision.
  final GameSave save;

  /// `states[k]` is the state right after decision `k` (`states[0]` is the
  /// start of the match), exactly as `Engine.apply` returned it.
  final List<GameState> states;

  /// Every die rolled, including passes and forfeits, with the number of
  /// decisions made when it was rolled.
  final List<({int decisions, int value})> rolls;

  GameState get last => states.last;
  int get decisions => states.length - 1;
}

/// Plays [setup] with seed [seed], choosing legal moves with [pick].
Played play(
  MatchSetup setup,
  int seed,
  Random pick, {
  int maxDecisions = 5000,
}) {
  var state = setup.newGame(seed);
  var save = GameSave.begin(id: 'g$seed', now: t0, setup: setup, seed: seed);
  final states = <GameState>[state];
  final rolls = <({int decisions, int value})>[];
  var clock = t0;
  while (!state.isOver && states.length - 1 < maxDecisions) {
    while (!state.isOver && !state.awaitingMove) {
      final rolled = Engine.roll(state);
      rolls.add((decisions: states.length - 1, value: rolled.value));
      state = rolled.state;
    }
    if (state.isOver) {
      break;
    }
    final moves = Engine.legalMoves(state);
    final move = moves[pick.nextInt(moves.length)];
    final entry = Engine.logEntry(state, move);
    final after = Engine.apply(state, move);
    clock = clock.add(const Duration(seconds: 3));
    save = save.withEntry(entry, after, clock);
    state = after;
    states.add(state);
  }
  return Played(
    setup: setup,
    seed: seed,
    save: save,
    states: states,
    rolls: rolls,
  );
}

/// The setups the property tests cover: the three presets at 2, 3 and 4
/// players, teams with and without teammate control, banked rolls and the
/// blockade options, with a few AI seats and names.
List<({String name, MatchSetup setup})> setupMatrix() {
  final presets = <String, RulesConfig>{
    'classic': const RulesConfig.classic(),
    'quick': const RulesConfig.quick(),
    'strategic': const RulesConfig.strategic(),
  };
  final out = <({String name, MatchSetup setup})>[];
  void add(String name, MatchSetup setup) =>
      out.add((name: name, setup: setup));

  for (final entry in presets.entries) {
    final rules = entry.value;
    for (final players in [2, 3, 4]) {
      add('${entry.key} $players p',
          MatchSetup.hotSeat(players: players, rules: rules));
    }
    add('${entry.key} teams control',
        MatchSetup.hotSeat(rules: rules, teams: true));
    add(
      '${entry.key} teams no control',
      MatchSetup.hotSeat(
        rules: rules.copyWith(teammateControl: false),
        teams: true,
      ),
    );
    final banked = rules.copyWith(bankedRolls: true);
    add('${entry.key} banked 2 p',
        MatchSetup.hotSeat(players: 2, rules: banked));
    add('${entry.key} banked 4 p', MatchSetup.hotSeat(rules: banked));
    add('${entry.key} banked teams',
        MatchSetup.hotSeat(rules: banked, teams: true));
  }

  final blockade = const RulesConfig.strategic();
  add(
    'blockade movement',
    MatchSetup.hotSeat(rules: blockade.copyWith(blockadeMovement: true)),
  );
  add(
    'blockade full options',
    MatchSetup.hotSeat(
      rules: blockade.copyWith(
        blockadeMovement: true,
        blockadeCapture: true,
        blockadeUnbreakable: true,
        pieceOnBlockade: true,
        blockadeFormFromSafe: false,
      ),
    ),
  );
  add(
    'blockade friendly restriction teams',
    MatchSetup.hotSeat(
      rules: blockade.copyWith(blockadeFriendlyRestriction: true),
      teams: true,
    ),
  );
  add(
    'blockade banked',
    MatchSetup.hotSeat(
      rules: blockade.copyWith(bankedRolls: true, blockadeMovement: true),
    ),
  );
  add(
    'ai seats',
    MatchSetup.hotSeat(rules: const RulesConfig.classic())
        .withSeat(
            1,
            const SeatConfig(
                type: SeatType.ai, aiLevel: AiLevel.hard, name: 'Bot'))
        .withSeat(
            3, const SeatConfig(type: SeatType.ai, aiLevel: AiLevel.easy)),
  );
  return out;
}
