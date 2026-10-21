import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

void main() {
  const bot = GreedyBot();

  Move pick(GameState state) => bot.choose(state, Engine.legalMoves(state));

  group('GreedyBot choices', () {
    test('prefers a capture over a plain advance', () {
      // Seat 0 can walk 2 -> 6 or 20 -> 24; a seat 1 token sits on square 24.
      final state = makeState(
        tokens: {
          0: [2, 20, -1, -1],
          1: [relativeFor(1, 24), -1, -1, -1],
        },
        dice: 4,
      );
      expect(pick(state).tokenIndex, 1);
    });

    test('prefers reaching home', () {
      final state = makeState(
        tokens: {
          0: [10, 52, -1, -1],
        },
        dice: 4,
      );
      final move = pick(state);
      expect(move.tokenIndex, 1);
      expect(move.to, finishPosition);
    });

    test('brings a token out of the yard on a six', () {
      final state = makeState(
        tokens: {
          0: [10, -1, -1, -1],
        },
        dice: 6,
      );
      expect(pick(state).from, yardPosition);
    });

    test('avoids stepping in front of an opponent', () {
      // Token 0 (30 -> 33) would land 2 squares ahead of a seat 1 token on
      // square 31; token 1 (20 -> 23) is out of reach.
      final state = makeState(
        tokens: {
          0: [30, 20, -1, -1],
          1: [relativeFor(1, 31), -1, -1, -1],
        },
        dice: 3,
      );
      expect(pick(state).tokenIndex, 1);
    });

    test('likes a safe square', () {
      // 5 -> 8 (safe star) beats 12 -> 15 with the same progress.
      final state = makeState(
        tokens: {
          0: [12, 5, -1, -1],
        },
        dice: 3,
      );
      expect(pick(state).tokenIndex, 1);
    });

    test('landing on a partner is no capture', () {
      final state = makeState(
        rules: const RulesConfig(teamsEnabled: true),
        tokens: {
          0: [2, 20, -1, -1],
          2: [relativeFor(2, 24), -1, -1, -1],
        },
        dice: 4,
      );
      final landing =
          Engine.legalMoves(state).firstWhere((m) => m.to == 24 - 0);
      expect(bot.score(state, landing), lessThan(GreedyBot.captureBonus));
    });

    test('is deterministic and rejects an empty list', () {
      final state = makeState(
        tokens: {
          0: [3, 9, 14, 20],
        },
        dice: 5,
      );
      expect(pick(state), pick(state));
      expect(() => bot.choose(state, const []), throwsArgumentError);
    });
  });

  group('GreedyBot playouts', () {
    const presets = {
      'classic': RulesConfig.classic(),
      'quick': RulesConfig.quick(),
      'strategic': RulesConfig.strategic(),
    };
    final tables = {
      '2 players': MatchSetup.hotSeat(players: 2),
      '3 players': MatchSetup.hotSeat(players: 3),
      '4 players': MatchSetup.hotSeat(),
      'teams': MatchSetup.hotSeat().withTeams(true),
    };

    for (final preset in presets.entries) {
      for (final table in tables.entries) {
        for (final banked in [false, true]) {
          test(
              '${preset.key}, ${table.key}${banked ? ', banked' : ''}: '
              'bots finish legal games', () {
            final setup = table.value.withRules(
              preset.value.copyWith(bankedRolls: banked),
            );
            for (var seed = 1; seed <= 4; seed++) {
              var state = setup.newGame(seed);
              var decisions = 0;
              while (true) {
                state = Engine.nextDecision(state);
                if (state.isOver) {
                  break;
                }
                final legal = Engine.legalMoves(state);
                final move = bot.choose(state, legal);
                expect(legal, contains(move));
                state = Engine.apply(state, move);
                decisions++;
                expect(decisions, lessThan(20000), reason: 'game $seed');
              }
              expect(state.isOver, isTrue);
              expect(state.ranking, isNotEmpty);
            }
          });
        }
      }
    }
  });
}
