import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('six and home bonuses', () {
    test('a 6 grants a bonus turn', () {
      final state = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, dice: 6);
      final after = play(state, 0);
      expect(after.currentSeat, 0);
      expect(after.dice, isNull);
      expect(after.awaitingRoll, isTrue);
    });

    test('no bonus for a 6 when extraTurnOnSix is false', () {
      final state = makeState(
        rules: const RulesConfig(extraTurnOnSix: false),
        tokens: {
          0: [5, -1, -1, -1]
        },
        dice: 6,
      );
      expect(play(state, 0).currentSeat, 1);
    });

    test('reaching home grants a bonus turn', () {
      final state = makeState(tokens: {
        0: [53, 5, -1, -1]
      }, dice: 3);
      expect(play(state, 0).currentSeat, 0);
    });

    test('no bonus for reaching home when extraTurnOnHome is false', () {
      final state = makeState(
        rules: const RulesConfig(extraTurnOnHome: false),
        tokens: {
          0: [53, 5, -1, -1]
        },
        dice: 3,
      );
      expect(play(state, 0).currentSeat, 1);
    });

    test('the sixes counter survives a bonus turn', () {
      final rng = findRngState([6]);
      var state = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, rngState: rng);
      final rolled = Engine.roll(state);
      expect(rolled.state.consecutiveSixes, 1);
      state = play(rolled.state, 0);
      expect(state.currentSeat, 0);
      expect(state.consecutiveSixes, 1);
    });
  });

  group('turn rotation', () {
    test('a normal move passes the turn clockwise', () {
      final state = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, dice: 3);
      final after = play(state, 0);
      expect(after.currentSeat, 1);
      expect(after.turnNumber, 1);
      expect(after.consecutiveSixes, 0);
    });

    test('inactive seats are skipped', () {
      final state = makeState(
        activeSeats: const [0, 2],
        tokens: {
          0: [5, -1, -1, -1],
          2: [5, -1, -1, -1]
        },
        dice: 3,
      );
      final after = play(state, 0);
      expect(after.currentSeat, 2);
      final back = play(withTokens(after, {}, dice: 3), 0);
      expect(back.currentSeat, 0);
    });

    test('three players rotate 0 -> 1 -> 2 -> 0', () {
      var state = makeState(
        activeSeats: const [0, 1, 2],
        tokens: {
          0: [5, -1, -1, -1],
          1: [5, -1, -1, -1],
          2: [5, -1, -1, -1],
        },
        dice: 3,
      );
      final order = <int>[];
      for (var i = 0; i < 4; i++) {
        state = play(state.copyWith(dice: 3), 0);
        order.add(state.currentSeat);
      }
      expect(order, [1, 2, 0, 1]);
    });
  });

  group('rolling', () {
    test('roll draws the next die from the seeded PRNG', () {
      final rng = findRngState([4]);
      final state = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, rngState: rng);
      final result = Engine.roll(state);
      expect(result.value, 4);
      expect(result.outcome, RollOutcome.awaitingMove);
      expect(result.state.dice, 4);
      expect(result.state.rngState, Dice.roll(rng).nextState);
    });

    test('no legal move: the turn passes automatically', () {
      final rng = findRngState([3]);
      final state = makeState(rngState: rng); // all tokens in the yard
      final result = Engine.roll(state);
      expect(result.value, 3);
      expect(result.outcome, RollOutcome.noLegalMoves);
      expect(result.state.currentSeat, 1);
      expect(result.state.dice, isNull);
      expect(result.state.turnNumber, 1);
    });

    test('a bonus turn with no legal move ends cleanly', () {
      final rng = findRngState([3]);
      final state = makeState(rngState: rng, consecutiveSixes: 1);
      final result = Engine.roll(state);
      expect(result.outcome, RollOutcome.noLegalMoves);
      expect(result.state.currentSeat, 1);
      expect(result.state.consecutiveSixes, 0);
    });

    test('a 6 with no legal move also passes the turn', () {
      final rng = findRngState([6]);
      final state = makeState(
        tokens: {
          0: [53, 53, 53, 53]
        }, // overshoot for everything but a 3
        rngState: rng,
      );
      // 6 would let nothing move: yard is empty and 53+6 overshoots.
      final result = Engine.roll(state);
      expect(result.outcome, RollOutcome.noLegalMoves);
      expect(result.state.currentSeat, 1);
    });

    test('rolling is refused while a move is pending', () {
      final state = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, dice: 3);
      expect(() => Engine.roll(state), throwsStateError);
    });

    test('nextDecision rolls through passes until a choice is needed', () {
      final state = Engine.nextDecision(Engine.newGame(seed: 99));
      expect(state.dice, isNotNull);
      expect(Engine.legalMoves(state), isNotEmpty);
    });
  });

  group('triple six', () {
    test('the third consecutive 6 forfeits the turn', () {
      final rng = findRngState([6, 6, 6]);
      var state = makeState(tokens: {
        0: [10, -1, -1, -1]
      }, rngState: rng);

      final first = Engine.roll(state);
      expect(first.outcome, RollOutcome.awaitingMove);
      state = play(first.state, 0);
      expect(state.tokens[0][0], 16);
      expect(state.currentSeat, 0);

      final second = Engine.roll(state);
      expect(second.outcome, RollOutcome.awaitingMove);
      expect(second.state.consecutiveSixes, 2);
      state = play(second.state, 0);
      expect(state.tokens[0][0], 22);

      final third = Engine.roll(state);
      expect(third.value, 6);
      expect(third.outcome, RollOutcome.tripleSixForfeit);
      // The third 6 is never played: tokens unchanged, turn advanced.
      expect(third.state.tokens[0], [22, -1, -1, -1]);
      expect(third.state.currentSeat, 1);
      expect(third.state.dice, isNull);
      expect(third.state.consecutiveSixes, 0);
    });

    test('with the rule off, a third 6 is playable', () {
      final rng = findRngState([6, 6, 6]);
      var state = makeState(
        rules: const RulesConfig(tripleSixForfeit: false),
        tokens: {
          0: [10, -1, -1, -1]
        },
        rngState: rng,
      );
      for (var i = 0; i < 2; i++) {
        state = play(Engine.roll(state).state, 0);
      }
      final third = Engine.roll(state);
      expect(third.outcome, RollOutcome.awaitingMove);
      expect(third.state.consecutiveSixes, 3);
    });

    test('a non-6 resets the consecutive counter', () {
      final rng = findRngState([3]);
      final state = makeState(
        tokens: {
          0: [10, -1, -1, -1]
        },
        consecutiveSixes: 2,
        rngState: rng,
      );
      final result = Engine.roll(state);
      expect(result.outcome, RollOutcome.awaitingMove);
      expect(result.state.consecutiveSixes, 0);
    });

    test('also applies when a finished player rolls for their teammate', () {
      final rng = findRngState([6]);
      final state = makeState(
        rules: const RulesConfig(teamsEnabled: true),
        tokens: {
          0: [56, 56, 56, 56],
          2: [10, -1, -1, -1],
        },
        currentSeat: 0,
        consecutiveSixes: 2,
        rngState: rng,
        finishOrder: const [0],
      );
      expect(state.controlledSeat, 2);

      final result = Engine.roll(state);
      expect(result.outcome, RollOutcome.tripleSixForfeit);
      expect(result.state.tokens[2], [10, -1, -1, -1]);
      expect(result.state.currentSeat, 1);
    });
  });

  group('state determinism and reproducibility', () {
    test('same seed + same decisions give the identical state', () {
      final a = playOut(seed: 31337, chooser: Random(1));
      final b = playOut(seed: 31337, chooser: Random(1));
      expect(a.finished, isTrue);
      expect(a.state, b.state);
      expect(a.state.hashCode, b.state.hashCode);
      expect(a.log, b.log);
    });

    test('different seeds diverge', () {
      final a = playOut(seed: 1, chooser: Random(1));
      final b = playOut(seed: 2, chooser: Random(1));
      expect(a.state, isNot(b.state));
    });

    for (final entry in {
      'classic': const RulesConfig.classic(),
      'quick': const RulesConfig.quick(),
      'strategic': const RulesConfig.strategic(),
    }.entries) {
      test('replaying seed + move log rebuilds the game (${entry.key})', () {
        final played =
            playOut(seed: 2024, chooser: Random(7), rules: entry.value);
        expect(played.finished, isTrue);
        final replayed = Engine.replay(
          seed: 2024,
          log: played.log,
          rules: entry.value,
        );
        expect(replayed, played.state);
      });
    }

    test('replaying any prefix of the log matches the live game', () {
      final played = playOut(seed: 5, chooser: Random(5));
      expect(played.log.length, greaterThan(100));
      for (final k in [1, 2, 10, 40, 100, played.log.length]) {
        final replayed =
            Engine.replay(seed: 5, log: played.log.take(k).toList());
        expect(replayed, played.afterMoves[k - 1], reason: 'after $k moves');
      }
    });

    test('a log entry that does not match the state is rejected', () {
      final state = Engine.nextDecision(Engine.newGame(seed: 11));
      final move = Engine.legalMoves(state).first;
      final good = Engine.logEntry(state, move);
      final wrongDice = MoveLogEntry(
        seat: good.seat,
        dice: good.dice == 6 ? 5 : good.dice + 1,
        tokenIndex: good.tokenIndex,
      );
      expect(
        () => Engine.applyEntry(state, wrongDice),
        throwsA(isA<IllegalMoveException>()),
      );
      final wrongSeat = MoveLogEntry(
        seat: (good.seat + 1) % 4,
        dice: good.dice,
        tokenIndex: good.tokenIndex,
      );
      expect(
        () => Engine.applyEntry(state, wrongSeat),
        throwsA(isA<IllegalMoveException>()),
      );
      expect(Engine.applyEntry(state, good), Engine.apply(state, move));
    });
  });

  group('illegal input is rejected', () {
    test('apply without a pending roll', () {
      final state = makeState(tokens: {
        0: [5, -1, -1, -1]
      });
      expect(
        () => Engine.apply(
          state,
          const Move(owner: 0, tokenIndex: 0, from: 5, to: 8),
        ),
        throwsA(isA<IllegalMoveException>()),
      );
    });

    test('apply of a token that cannot move', () {
      final state = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, dice: 3);
      expect(
        () => Engine.apply(
          state,
          const Move(owner: 0, tokenIndex: 1, from: -1, to: 0),
        ),
        throwsA(isA<IllegalMoveException>()),
      );
    });

    test('apply of another seat\'s token', () {
      final state = makeState(
        tokens: {
          0: [5, -1, -1, -1],
          1: [5, -1, -1, -1],
        },
        dice: 3,
      );
      expect(
        () => Engine.apply(
          state,
          const Move(owner: 1, tokenIndex: 0, from: 5, to: 8),
        ),
        throwsA(isA<IllegalMoveException>()),
      );
    });

    test('forged from/to values are ignored', () {
      final state = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, dice: 3);
      final after = Engine.apply(
        state,
        const Move(owner: 0, tokenIndex: 0, from: 5, to: 50),
      );
      expect(after.tokens[0][0], 8);
    });

    test('legalMoves needs a die and a valid face', () {
      final state = makeState();
      expect(() => Engine.legalMoves(state), throwsStateError);
      expect(() => Engine.legalMoves(state, 7), throwsArgumentError);
      expect(Engine.legalMoves(state, 6), hasLength(4));
    });
  });

  group('newGame', () {
    test('starts with every token in the yard, first seat to move', () {
      final state = Engine.newGame(seed: 1, activeSeats: const [2, 0]);
      expect(state.activeSeats, [0, 2]);
      expect(state.currentSeat, 0);
      expect(state.tokens.expand((t) => t).every((p) => p == yardPosition),
          isTrue);
      expect(state.awaitingRoll, isTrue);
    });

    test('validates the seat list', () {
      expect(() => Engine.newGame(seed: 1, activeSeats: const [0]),
          throwsArgumentError);
      expect(
        () => Engine.newGame(seed: 1, activeSeats: const [0, 0, 1]),
        throwsArgumentError,
      );
      expect(
        () => Engine.newGame(seed: 1, activeSeats: const [0, 4]),
        throwsArgumentError,
      );
      expect(
        () => Engine.newGame(
          seed: 1,
          rules: const RulesConfig(teamsEnabled: true),
          activeSeats: const [0, 1, 2],
        ),
        throwsArgumentError,
      );
    });

    test('state is immutable', () {
      final state = Engine.newGame(seed: 1);
      expect(() => state.tokens[0][0] = 5, throwsUnsupportedError);
      expect(() => state.tokens.add([]), throwsUnsupportedError);
      expect(() => state.finishOrder.add(0), throwsUnsupportedError);
    });

    test('applying a move leaves the previous state untouched', () {
      final before = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, dice: 3);
      final snapshot = before.toString();
      play(before, 0);
      expect(before.toString(), snapshot);
    });
  });
}
