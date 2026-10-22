import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const blockadeRules = RulesConfig(blockades: true);
  const teamBlockadeRules = RulesConfig(blockades: true, teamsEnabled: true);

  /// Seat 0 token at relative 5 (absolute 5), seat 1 blockade on [square].
  GameState opponentBlockade(int square, {RulesConfig rules = blockadeRules}) {
    return makeState(
      rules: rules,
      tokens: {
        0: [5, -1, -1, -1],
        1: [relativeFor(1, square), relativeFor(1, square), -1, -1],
      },
    );
  }

  group('opponent blockades', () {
    test('cannot be landed on', () {
      final state = opponentBlockade(10).copyWith(dice: 5);
      expect(canMove(state, 0), isFalse);
    });

    test('cannot be passed even if the roll exceeds it', () {
      final state = opponentBlockade(10).copyWith(dice: 6);
      expect(canMove(state, 0), isFalse);
    });

    test('do not affect rolls that stop short of them', () {
      final state = opponentBlockade(10).copyWith(dice: 4);
      expect(canMove(state, 0), isTrue);
    });

    test('do not affect moves that start beyond them', () {
      final state = makeState(
        rules: blockadeRules,
        tokens: {
          0: [11, -1, -1, -1],
          1: [relativeFor(1, 10), relativeFor(1, 10), -1, -1],
        },
        dice: 6,
      );
      expect(canMove(state, 0), isTrue);
    });

    test('do not affect blockades past the destination', () {
      final state = opponentBlockade(20).copyWith(dice: 6);
      expect(canMove(state, 0), isTrue);
    });

    test('are ignored when the blockades rule is off', () {
      final state = opponentBlockade(
        10,
        rules: const RulesConfig(),
      ).copyWith(dice: 6);
      expect(canMove(state, 0), isTrue);
    });

    test('a single opponent token is not a blockade (it is captured)', () {
      final state = makeState(
        rules: blockadeRules,
        tokens: {
          0: [5, -1, -1, -1],
          1: [relativeFor(1, 10), -1, -1, -1],
        },
        dice: 5,
      );
      final after = play(state, 0);
      expect(after.tokens[1][0], yardPosition);
    });

    test('on a safe square block nobody (safe squares stay open)', () {
      final landing = opponentBlockade(8).copyWith(dice: 3);
      expect(canMove(landing, 0), isTrue);
      final passing = opponentBlockade(8).copyWith(dice: 4);
      expect(canMove(passing, 0), isTrue);
      // Sharing the safe square captures nobody.
      final after = play(landing, 0);
      expect(after.tokens[1].take(2), everyElement(relativeFor(1, 8)));
    });

    test(
        'on the owner\'s own start square they do block (formed out of '
        'the yard)', () {
      // Seat 1's start square is absolute 13.
      GameState atStart(int d) => makeState(
            rules: blockadeRules,
            tokens: {
              0: [10, -1, -1, -1],
              1: [0, 0, -1, -1],
            },
            dice: d,
          );
      expect(canMove(atStart(3), 0), isFalse); // lands on 13
      expect(canMove(atStart(5), 0), isFalse); // passes 13
      expect(canMove(atStart(2), 0), isTrue); // stops short of it
    });

    test(
        'a pair of the owner forms from the yard square: two tokens leaving '
        'the yard make a blockade at once', () {
      final state = makeState(
        rules: blockadeRules,
        tokens: {
          1: [0, -1, -1, -1],
          0: [10, -1, -1, -1],
        },
        currentSeat: 1,
        dice: 6,
      );
      final after = play(state, 1); // second token leaves the yard
      expect(after.tokens[1].take(2), [0, 0]);
      final next = after.copyWith(currentSeat: 0, dice: 5);
      expect(canMove(next, 0), isFalse); // 10 -> 15 passes square 13
    });

    test('on the last track square block the way into the home column', () {
      GameState at48(int d) => makeState(
            rules: blockadeRules,
            tokens: {
              0: [48, -1, -1, -1],
              1: [relativeFor(1, 50), relativeFor(1, 50), -1, -1],
            },
            dice: d,
          );
      expect(canMove(at48(1), 0), isTrue); // 49
      expect(canMove(at48(2), 0), isFalse); // lands on 50
      expect(canMove(at48(3), 0), isFalse); // 51, passes 50
      expect(canMove(at48(6), 0), isFalse); // 54, passes 50
    });

    test(
        'of another seat on this start square do not keep a yard token '
        'inside', () {
      // A pair on a start square that is not their own is on a safe square.
      final state = makeState(
        rules: blockadeRules,
        tokens: {
          1: [relativeFor(1, 0), relativeFor(1, 0), -1, -1],
        },
        dice: 6,
      );
      expect(Engine.legalMoves(state), isNotEmpty);
    });

    test('block every opposing seat, not only the next one', () {
      for (final owner in [1, 2, 3]) {
        final state = makeState(
          rules: blockadeRules,
          tokens: {
            0: [5, -1, -1, -1],
            owner: [relativeFor(owner, 10), relativeFor(owner, 10), -1, -1],
          },
          dice: 5,
        );
        expect(canMove(state, 0), isFalse, reason: 'seat $owner');
      }
    });

    test('are not blockades if the two tokens are on different squares', () {
      final state = makeState(
        rules: blockadeRules,
        tokens: {
          0: [5, -1, -1, -1],
          1: [relativeFor(1, 10), relativeFor(1, 11), -1, -1],
        },
        dice: 6,
      );
      // Passes 10 (single) and captures nothing at 11? 5+6 = 11 -> captured.
      expect(canMove(state, 0), isTrue);
    });
  });

  group('forming blockades', () {
    test('the block stops a follower from passing or landing', () {
      final state = makeState(
        rules: blockadeRules,
        tokens: {
          0: [10, 10, -1, -1],
          1: [relativeFor(1, 8), -1, -1, -1],
        },
        currentSeat: 1,
      );
      expect(canMove(state, 0, 1), isTrue); // 9
      expect(canMove(state, 0, 2), isFalse); // lands on 10
      expect(canMove(state, 0, 4), isFalse); // passes 10
    });

    test('moving one token away dissolves the block', () {
      final state = makeState(
        rules: blockadeRules,
        tokens: {
          0: [10, 10, -1, -1],
          1: [relativeFor(1, 8), -1, -1, -1],
        },
        dice: 3,
      );
      final after = play(state, 0);
      expect(after.tokens[0].sublist(0, 2), [13, 10]);
      expect(canMove(after, 0, 4), isTrue);
    });
  });

  group('own and teammate blockades', () {
    test('the owner may land on and pass their own blockade', () {
      final state = makeState(
        rules: blockadeRules,
        tokens: {
          0: [5, 10, 10, -1],
        },
        dice: 5,
      );
      expect(canMove(state, 0), isTrue); // lands on own block
      expect(canMove(state.copyWith(dice: 6), 0), isTrue); // passes it
    });

    GameState teammateBlock(int square, int dice) => makeState(
          rules: teamBlockadeRules,
          tokens: {
            0: [5, -1, -1, -1],
            2: [relativeFor(2, square), relativeFor(2, square), -1, -1],
          },
          dice: dice,
        );

    test('teammates may pass through a blockade', () {
      expect(canMove(teammateBlock(10, 6), 0), isTrue);
    });

    test('teammates may not land on a blockade of a non-safe square', () {
      expect(canMove(teammateBlock(10, 5), 0), isFalse);
    });

    test('teammates may land on a blockade of a safe square', () {
      expect(canMove(teammateBlock(8, 3), 0), isTrue);
    });

    test('the other team is still blocked in team play', () {
      final state = makeState(
        rules: teamBlockadeRules,
        tokens: {
          1: [relativeFor(1, 5), -1, -1, -1],
          2: [relativeFor(2, 10), relativeFor(2, 10), -1, -1],
        },
        currentSeat: 1,
        dice: 6,
      );
      expect(canMove(state, 0), isFalse);
    });
  });
}
