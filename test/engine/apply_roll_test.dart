import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Rule sets covering every path `applyRoll` / `applyLegal` can take.
final Map<String, RulesConfig> _configs = {
  'classic': const RulesConfig.classic(),
  'quick': const RulesConfig.quick(),
  'strategic': const RulesConfig.strategic(),
  'blockade options': const RulesConfig(
    blockades: true,
    blockadeMovement: true,
    blockadeCapture: true,
    pieceOnBlockade: true,
  ),
  'banked': const RulesConfig(bankedRolls: true),
  'banked strategic': const RulesConfig(bankedRolls: true, blockades: true),
  'teams': const RulesConfig(teamsEnabled: true),
};

/// Walks random games and calls [visit] for every state reached.
void _walk(
  RulesConfig rules,
  int seed,
  void Function(GameState state) visit,
) {
  final chooser = Random(seed);
  var state = Engine.newGame(seed: seed, rules: rules);
  for (var step = 0; step < 4000 && !state.isOver; step++) {
    visit(state);
    if (state.awaitingMove) {
      final moves = Engine.legalMoves(state);
      state = Engine.apply(state, moves[chooser.nextInt(moves.length)]);
    } else {
      state = Engine.roll(state).state;
    }
  }
}

void main() {
  group('Engine.applyRoll (E1)', () {
    for (final entry in _configs.entries) {
      test('agrees with roll: ${entry.key}', () {
        var checked = 0;
        for (var seed = 1; seed <= 12; seed++) {
          _walk(entry.value, seed, (state) {
            if (!state.awaitingRoll) {
              return;
            }
            final rolled = Engine.roll(state);
            final supplied = Engine.applyRoll(state, Dice.roll(state.rngState));
            expect(supplied.state, rolled.state);
            expect(supplied.value, rolled.value);
            expect(supplied.outcome, rolled.outcome);
            checked++;
          });
        }
        expect(checked, greaterThan(100));
      });

      test('keeps rngState when handed the same one: ${entry.key}', () {
        for (var seed = 1; seed <= 6; seed++) {
          _walk(entry.value, seed, (state) {
            if (!state.awaitingRoll) {
              return;
            }
            for (var face = 1; face <= 6; face++) {
              final result =
                  Engine.applyRoll(state, DiceRoll(face, state.rngState));
              expect(result.value, face);
              expect(result.state.rngState, state.rngState);
            }
          });
        }
      });
    }

    test('every face reaches the forfeit, pass and move outcomes', () {
      final outcomes = <RollOutcome>{};
      for (final rules in _configs.values) {
        for (var seed = 1; seed <= 12; seed++) {
          _walk(rules, seed, (state) {
            if (!state.awaitingRoll) {
              return;
            }
            for (var face = 1; face <= 6; face++) {
              outcomes.add(
                Engine.applyRoll(state, DiceRoll(face, 0)).outcome,
              );
            }
          });
        }
      }
      expect(outcomes, containsAll(RollOutcome.values));
    });

    test('rejects an impossible face and a finished game', () {
      final state = Engine.newGame(seed: 1);
      expect(
        () => Engine.applyRoll(state, const DiceRoll(7, 0)),
        throwsArgumentError,
      );
      expect(
        () => Engine.applyRoll(state, const DiceRoll(0, 0)),
        throwsArgumentError,
      );
      final over = makeState(
        rules: const RulesConfig(endMode: EndMode.firstToWin),
        tokens: {
          0: [56, 56, 56, 56],
        },
      );
      expect(over.isOver, isTrue);
      expect(
        () => Engine.applyRoll(over, const DiceRoll(3, 0)),
        throwsStateError,
      );
    });

    test('a forfeit on the third six follows the supplied face', () {
      final state = makeState(
        tokens: {
          0: [5, -1, -1, -1],
        },
        consecutiveSixes: 2,
      );
      final six = Engine.applyRoll(state, DiceRoll(6, state.rngState));
      expect(six.outcome, RollOutcome.tripleSixForfeit);
      expect(six.state.currentSeat, 1);
      final three = Engine.applyRoll(state, DiceRoll(3, state.rngState));
      expect(three.outcome, RollOutcome.awaitingMove);
      expect(three.state.dice, 3);
    });
  });

  group('Engine.applyLegal (E2)', () {
    for (final entry in _configs.entries) {
      test('equals apply for every legal move: ${entry.key}', () {
        var checked = 0;
        for (var seed = 1; seed <= 12; seed++) {
          _walk(entry.value, seed, (state) {
            if (!state.awaitingMove) {
              return;
            }
            for (final move in Engine.legalMoves(state)) {
              expect(Engine.applyLegal(state, move), Engine.apply(state, move));
              checked++;
            }
          });
        }
        expect(checked, greaterThan(100));
      });
    }

    test('does not validate: a forged move is the caller\'s problem', () {
      final state = makeState(
        tokens: {
          0: [5, -1, -1, -1],
        },
        dice: 3,
      );
      const forged = Move(owner: 0, tokenIndex: 1, from: -1, to: 0);
      expect(() => Engine.apply(state, forged), throwsA(isA<Exception>()));
      // applyLegal trusts the move; it must not throw the validation error.
      expect(() => Engine.applyLegal(state, forged),
          isNot(throwsA(isA<IllegalMoveException>())));
    });
  });
}
