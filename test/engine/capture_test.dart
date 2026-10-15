import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('open square capture', () {
    test('landing on an opponent sends it back to the yard', () {
      final state = makeState(
        tokens: {
          0: [5, -1, -1, -1],
          1: [relativeFor(1, 10), -1, -1, -1],
        },
        dice: 5,
      );
      final after = play(state, 0);
      expect(after.tokens[0][0], 10);
      expect(after.tokens[1][0], yardPosition);
    });

    test('captures after wrapping around absolute square 51', () {
      // Seat 3 token on absolute 50 (relative 11) rolls 4 -> absolute 2.
      final state = makeState(
        tokens: {
          3: [11, -1, -1, -1],
          1: [relativeFor(1, 2), -1, -1, -1],
        },
        currentSeat: 3,
        dice: 4,
      );
      final after = play(state, 0);
      expect(absoluteSquare(3, after.tokens[3][0]), 2);
      expect(after.tokens[1][0], yardPosition);
    });

    test('only the landing square captures, not squares passed over', () {
      final state = makeState(
        tokens: {
          0: [5, -1, -1, -1],
          1: [relativeFor(1, 7), -1, -1, -1],
        },
        dice: 5,
      );
      final after = play(state, 0);
      expect(after.tokens[1][0], relativeFor(1, 7));
    });

    test('a token in the home column is never captured', () {
      final state = makeState(
        tokens: {
          0: [45, -1, -1, -1],
          1: [52, -1, -1, -1],
        },
        dice: 6,
      );
      final after = play(state, 0);
      expect(after.tokens[1][0], 52);
    });

    test('with blockades off, every stacked opponent token is captured', () {
      final state = makeState(
        tokens: {
          0: [5, -1, -1, -1],
          1: [relativeFor(1, 10), relativeFor(1, 10), -1, -1],
        },
        dice: 5,
      );
      final after = play(state, 0);
      expect(after.tokens[1][0], yardPosition);
      expect(after.tokens[1][1], yardPosition);
    });

    test('captures reach every opponent seat, not just the next one', () {
      for (final victim in [1, 2, 3]) {
        final state = makeState(
          tokens: {
            0: [5, -1, -1, -1],
            victim: [relativeFor(victim, 10), -1, -1, -1],
          },
          dice: 5,
        );
        expect(play(state, 0).tokens[victim][0], yardPosition,
            reason: 'seat $victim');
      }
    });
  });

  group('safe squares', () {
    for (final square in safeSquares.toList()..sort()) {
      test('opponents coexist on safe square $square', () {
        final isStart = square == 0;
        final state = makeState(
          tokens: {
            0: [isStart ? -1 : square - 3, -1, -1, -1],
            1: [relativeFor(1, square), -1, -1, -1],
          },
          dice: isStart ? 6 : 3,
        );
        final after = play(state, 0);
        expect(after.tokens[0][0], square);
        expect(after.tokens[1][0], relativeFor(1, square));
        if (!isStart) {
          // No capture happened, so no capture bonus either.
          expect(after.currentSeat, 1);
        }
      });
    }

    test('a start square is safe for the opponent that sits on it', () {
      // Seat 1 token on its own start (absolute 13); seat 0 lands there.
      final state = makeState(
        tokens: {
          0: [10, -1, -1, -1],
          1: [0, -1, -1, -1],
        },
        dice: 3,
      );
      final after = play(state, 0);
      expect(after.tokens[1][0], 0);
    });
  });

  group('friendly immunity', () {
    test('landing on your own token never captures it', () {
      final state = makeState(tokens: {
        0: [5, 10, -1, -1]
      }, dice: 5);
      final after = play(state, 0);
      expect(after.tokens[0].sublist(0, 2), [10, 10]);
    });

    test('landing on a teammate never captures them', () {
      final state = makeState(
        rules: const RulesConfig(teamsEnabled: true),
        tokens: {
          0: [5, -1, -1, -1],
          2: [relativeFor(2, 10), -1, -1, -1],
        },
        dice: 5,
      );
      final after = play(state, 0);
      expect(after.tokens[0][0], 10);
      expect(after.tokens[2][0], relativeFor(2, 10));
      expect(after.currentSeat, 1, reason: 'no capture, so no bonus turn');
    });

    test('the other team is still captured in team play', () {
      final state = makeState(
        rules: const RulesConfig(teamsEnabled: true),
        tokens: {
          0: [5, -1, -1, -1],
          3: [relativeFor(3, 10), -1, -1, -1],
        },
        dice: 5,
      );
      expect(play(state, 0).tokens[3][0], yardPosition);
    });
  });

  group('extra turn on capture', () {
    GameState captureState(RulesConfig rules) => makeState(
          rules: rules,
          tokens: {
            0: [5, -1, -1, -1],
            1: [relativeFor(1, 10), -1, -1, -1],
          },
          dice: 5,
        );

    test('capturing awards a bonus turn when enabled', () {
      final after = play(captureState(const RulesConfig()), 0);
      expect(after.currentSeat, 0);
      expect(after.dice, isNull);
    });

    test('capturing passes the turn when disabled', () {
      final after = play(
        captureState(const RulesConfig(extraTurnOnCapture: false)),
        0,
      );
      expect(after.currentSeat, 1);
    });

    test('a move without a capture gives no bonus', () {
      final state = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, dice: 5);
      expect(play(state, 0).currentSeat, 1);
    });
  });
}
