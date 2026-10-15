import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('yard exit', () {
    for (var d = 1; d <= 5; d++) {
      test('cannot leave the yard on a $d when a six is needed', () {
        expect(Engine.legalMoves(makeState(dice: d)), isEmpty);
      });
    }

    test('leaves the yard onto square 0 on a 6', () {
      final moves = Engine.legalMoves(makeState(dice: 6));
      expect(moves, hasLength(4));
      for (final move in moves) {
        expect(move.from, yardPosition);
        expect(move.to, startPosition);
      }
    });

    for (var d = 1; d <= 6; d++) {
      test('leaves the yard on a $d when needSixToLeave is false', () {
        final state = makeState(
          rules: const RulesConfig(needSixToLeave: false),
          dice: d,
        );
        final moves = Engine.legalMoves(state);
        expect(moves, hasLength(4));
        expect(moves.every((m) => m.to == startPosition), isTrue);
      });
    }

    test('tokens already on the board still move without a 6', () {
      final state = makeState(tokens: {
        0: [5, -1, -1, -1]
      }, dice: 3);
      final moves = Engine.legalMoves(state);
      expect(moves.map((m) => m.tokenIndex), [0]);
      expect(moves.single.to, 8);
    });
  });

  group('home column and exact finish', () {
    test('a roll that overshoots the finish is illegal', () {
      final state = makeState(tokens: {
        0: [53, -1, -1, -1]
      }, dice: 4);
      expect(canMove(state, 0), isFalse);
    });

    test('an exact roll finishes', () {
      final state = makeState(tokens: {
        0: [53, -1, -1, -1]
      }, dice: 3);
      final move = Engine.legalMoves(state).single;
      expect(move.to, finishPosition);
    });

    test('rolls up to the exact distance advance inside the home column', () {
      for (var d = 1; d <= 5; d++) {
        final state = makeState(tokens: {
          0: [51, -1, -1, -1]
        }, dice: d);
        final move = Engine.legalMoves(state).single;
        expect(move.to, 51 + d, reason: 'roll $d');
      }
      expect(
          canMove(
              makeState(tokens: {
                0: [51, -1, -1, -1]
              }, dice: 6),
              0),
          isFalse);
    });

    test('with exactRollToFinish off an overshoot finishes the token', () {
      final state = makeState(
        rules: const RulesConfig(exactRollToFinish: false),
        tokens: {
          0: [53, -1, -1, -1]
        },
        dice: 6,
      );
      final move =
          Engine.legalMoves(state).singleWhere((m) => m.tokenIndex == 0);
      expect(move.to, finishPosition);
    });

    test('track walks into the home column', () {
      final state = makeState(tokens: {
        0: [50, -1, -1, -1]
      }, dice: 3);
      expect(Engine.legalMoves(state).single.to, 53);
    });

    test('finished tokens never move', () {
      final state = makeState(tokens: {
        0: [56, 56, 56, 56]
      }, dice: 6);
      expect(Engine.legalMoves(state), isEmpty);
    });
  });

  group('coordinate conversion', () {
    test('seat offsets are 13 squares apart', () {
      expect(absoluteSquare(0, 0), 0);
      expect(absoluteSquare(1, 0), 13);
      expect(absoluteSquare(2, 0), 26);
      expect(absoluteSquare(3, 0), 39);
    });

    test('positions wrap around square 51', () {
      expect(absoluteSquare(3, 13), 0);
      expect(absoluteSquare(3, 12), 51);
      expect(absoluteSquare(3, 50), 37);
      expect(absoluteSquare(2, 26), 0);
      expect(absoluteSquare(1, 50), 11);
      expect(absoluteSquare(0, 50), 50);
    });

    test(
        'each seat walks 51 distinct squares and never enters its own '
        'last-before-start square', () {
      for (var seat = 0; seat < 4; seat++) {
        final squares = {
          for (var rel = 0; rel <= lastTrackPosition; rel++)
            absoluteSquare(seat, rel),
        };
        expect(squares, hasLength(51));
        expect(squares.contains((seat * 13 + 51) % 52), isFalse);
      }
    });

    test('relative <-> absolute round trip across all seats', () {
      for (var seat = 0; seat < 4; seat++) {
        for (var rel = 0; rel <= lastTrackPosition; rel++) {
          expect(relativeFor(seat, absoluteSquare(seat, rel)), rel);
        }
      }
    });

    test('the 8 safe squares are the 4 starts and the 4 stars', () {
      expect(safeSquares, {0, 13, 26, 39, 8, 21, 34, 47});
      for (var seat = 0; seat < 4; seat++) {
        expect(isSafeSquare(absoluteSquare(seat, 0)), isTrue);
        expect(isSafeSquare(absoluteSquare(seat, 8)), isTrue);
      }
    });
  });
}
