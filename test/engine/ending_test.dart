import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _home = [56, 56, 56, 56];

void main() {
  const teams = RulesConfig(teamsEnabled: true);

  group('first to win', () {
    const rules = RulesConfig(endMode: EndMode.firstToWin);

    test('ends the instant the 4th token reaches home', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [56, 56, 56, 53],
          1: [10, -1, -1, -1],
        },
        dice: 3,
      );
      expect(state.isOver, isFalse);
      final after = play(state, 3);
      expect(after.isOver, isTrue);
      expect(after.finishOrder, [0]);
      expect(after.winners, [0]);
      expect(after.dice, isNull);
      expect(after.awaitingRoll, isFalse);
    });

    test('an over game accepts no more rolls or moves', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: _home,
          1: [10, -1, -1, -1],
        },
        finishOrder: const [0],
      );
      expect(() => Engine.roll(state), throwsStateError);
      expect(Engine.legalMoves(state, 3), isEmpty);
      expect(
        () => Engine.apply(
          state.copyWith(dice: 3),
          const Move(owner: 1, tokenIndex: 0, from: 10, to: 13),
        ),
        throwsA(isA<IllegalMoveException>()),
      );
    });

    test('an earlier token reaching home does not end the game', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [56, 56, 56, 52],
        },
        dice: 3,
      );
      expect(state.isOver, isFalse);
      expect(play(state, 3).isOver, isFalse);
    });
  });

  group('full ranking', () {
    test('records the finish order of a 4-player match', () {
      // Seat 0 finishes first.
      var state = makeState(
        tokens: {
          0: [56, 56, 56, 53],
          1: [10, -1, -1, -1],
        },
        dice: 3,
      );
      state = play(state, 3);
      expect(state.finishOrder, [0]);
      expect(state.isOver, isFalse);
      expect(state.currentSeat, 1, reason: 'finished seat gets no bonus turn');
      expect(state.ranking, [
        [0],
      ]);

      // Seat 1 finishes second.
      state = withTokens(
        state,
        {
          1: [56, 56, 56, 54],
        },
        currentSeat: 1,
        dice: 2,
      );
      state = play(state, 3);
      expect(state.finishOrder, [0, 1]);
      expect(state.isOver, isFalse);
      expect(state.currentSeat, 2);

      // Seat 2 finishes third; seat 3 is placed last automatically.
      state = withTokens(
        state,
        {
          2: [56, 56, 56, 55],
        },
        currentSeat: 2,
        dice: 1,
      );
      state = play(state, 3);
      expect(state.isOver, isTrue);
      expect(state.finishOrder, [0, 1, 2, 3]);
      expect(state.ranking, [
        [0],
        [1],
        [2],
        [3],
      ]);
      expect(state.winners, [0]);
    });

    test('finished seats are skipped in the turn cycle', () {
      final state = makeState(
        tokens: {
          0: _home,
          3: [10, -1, -1, -1],
        },
        currentSeat: 3,
        dice: 2,
        finishOrder: const [0],
      );
      expect(play(state, 0).currentSeat, 1);
    });

    test('a finished seat that would get a bonus turn does not roll again', () {
      final state = makeState(
        tokens: {
          0: [56, 56, 56, 50],
          1: [10, -1, -1, -1],
        },
        dice: 6,
      );
      final after = play(state, 3);
      expect(after.tokens[0], _home);
      expect(after.currentSeat, 1);
    });

    test('a 2-player match ends as soon as one seat finishes', () {
      final state = makeState(
        activeSeats: const [0, 2],
        tokens: {
          0: [56, 56, 56, 53],
          2: [10, -1, -1, -1],
        },
        dice: 3,
      );
      final after = play(state, 3);
      expect(after.isOver, isTrue);
      expect(after.finishOrder, [0, 2]);
      expect(after.ranking, [
        [0],
        [2],
      ]);
    });

    test('a 3-player match ranks 1st..3rd and auto-places the last seat', () {
      var state = makeState(
        activeSeats: const [0, 1, 2],
        tokens: {
          0: [56, 56, 56, 53],
          1: [10, -1, -1, -1],
          2: [20, -1, -1, -1],
        },
        dice: 3,
      );
      state = play(state, 3);
      expect(state.isOver, isFalse);
      expect(state.currentSeat, 1);

      state = withTokens(
        state,
        {
          1: [56, 56, 56, 54],
        },
        currentSeat: 1,
        dice: 2,
      );
      state = play(state, 3);
      expect(state.isOver, isTrue);
      expect(state.finishOrder, [0, 1, 2]);
    });

    test('seats may finish out of seating order', () {
      final state = makeState(
        tokens: {
          2: [56, 56, 56, 53],
        },
        currentSeat: 2,
        dice: 3,
      );
      final after = play(state, 3);
      expect(after.finishOrder, [2]);
      expect(after.currentSeat, 3);
    });

    test('ranking is empty before anyone finishes', () {
      final state = Engine.newGame(seed: 1);
      expect(state.ranking, isEmpty);
      expect(state.winners, isNull);
    });
  });

  group('team ranking', () {
    test('a team finishes only when both partners have all tokens home', () {
      final state = makeState(
        rules: teams,
        tokens: {
          0: [56, 56, 56, 53],
          2: [10, -1, -1, -1],
        },
        dice: 3,
      );
      final after = play(state, 3);
      expect(after.finishOrder, [0]);
      expect(after.seatFinished(0), isTrue);
      expect(after.unitFinished(0), isFalse);
      expect(after.isOver, isFalse);
      expect(after.ranking, isEmpty);
    });

    test('the match ends when the second partner gets home', () {
      final state = makeState(
        rules: teams,
        tokens: {
          0: _home,
          2: [56, 56, 56, 53],
        },
        currentSeat: 0, // finished: rolls for partner seat 2
        dice: 3,
        finishOrder: const [0],
      );
      expect(state.controlledSeat, 2);
      final moves = Engine.legalMoves(state);
      expect(moves.every((m) => m.owner == 2), isTrue);

      final after =
          Engine.apply(state, moves.singleWhere((m) => m.tokenIndex == 3));
      expect(after.isOver, isTrue);
      expect(after.finishOrder, [0, 2, 1, 3]);
      expect(after.ranking, [
        [0, 2],
        [1, 3],
      ]);
      expect(after.winners, [0, 2]);
    });

    test('teams are ranked by team outcome, not individual order', () {
      // Seat 1 (team B) finished before anyone on team A, but team A's
      // partners both finish before seat 3 does.
      final state = makeState(
        rules: teams,
        tokens: {
          0: _home,
          1: _home,
          2: [56, 56, 56, 53],
        },
        currentSeat: 0,
        dice: 3,
        finishOrder: const [1, 0],
      );
      final after = play(state, 3);
      expect(after.isOver, isTrue);
      expect(after.ranking, [
        [0, 2],
        [1, 3],
      ]);
      expect(after.winners, [0, 2]);
    });

    test('firstToWin in team play still needs both partners home', () {
      final state = makeState(
        rules: teams.copyWith(endMode: EndMode.firstToWin),
        tokens: {
          0: [56, 56, 56, 53],
          2: [10, -1, -1, -1],
        },
        dice: 3,
      );
      expect(play(state, 3).isOver, isFalse);
    });
  });

  group('teammate control', () {
    test('a finished player rolls for and moves their partner', () {
      final state = makeState(
        rules: teams,
        tokens: {
          0: _home,
          2: [10, -1, -1, -1],
        },
        currentSeat: 0,
        dice: 3,
        finishOrder: const [0],
      );
      final moves = Engine.legalMoves(state);
      expect(moves, hasLength(1));
      expect(moves.single.owner, 2);
      final after = Engine.apply(state, moves.single);
      expect(after.tokens[2][0], 13);
      expect(after.tokens[0], _home);
      expect(after.currentSeat, 1);
    });

    test('a 6 still grants the finished controller a bonus turn', () {
      final state = makeState(
        rules: teams,
        tokens: {
          0: _home,
          2: [10, -1, -1, -1],
        },
        currentSeat: 0,
        dice: 6,
        finishOrder: const [0],
      );
      final after = play(state, 0);
      expect(after.currentSeat, 0);
      expect(after.tokens[2][0], 16);
    });

    test('with no legal move for the partner the turn passes cleanly', () {
      final rng = findRngState([3]);
      final state = makeState(
        rules: teams,
        tokens: {0: _home}, // partner seat 2 is entirely in the yard
        currentSeat: 0,
        rngState: rng,
        finishOrder: const [0],
      );
      final result = Engine.roll(state);
      expect(result.outcome, RollOutcome.noLegalMoves);
      expect(result.state.currentSeat, 1);
    });

    test('the finished partner stays in the rotation', () {
      final state = makeState(
        rules: teams,
        tokens: {
          0: _home,
          2: [10, -1, -1, -1],
          3: [10, -1, -1, -1],
        },
        currentSeat: 3,
        dice: 2,
        finishOrder: const [0],
      );
      expect(play(state, 0).currentSeat, 0);
    });

    test('with teammateControl off finished players are skipped', () {
      final state = makeState(
        rules: teams.copyWith(teammateControl: false),
        tokens: {
          0: _home,
          2: [10, -1, -1, -1],
          3: [10, -1, -1, -1],
        },
        currentSeat: 3,
        dice: 2,
        finishOrder: const [0],
      );
      expect(play(state, 0).currentSeat, 1);
    });

    test('with teammateControl off the partner plays alone', () {
      final state = makeState(
        rules: teams.copyWith(teammateControl: false),
        tokens: {
          0: _home,
          2: [10, -1, -1, -1],
        },
        currentSeat: 2,
        dice: 2,
        finishOrder: const [0],
      );
      expect(state.controlledSeat, 2);
      expect(play(state, 0).currentSeat, 3);
    });

    test('reaching home as controller grants the usual bonus', () {
      final state = makeState(
        rules: teams,
        tokens: {
          0: _home,
          2: [53, 10, -1, -1],
        },
        currentSeat: 0,
        dice: 3,
        finishOrder: const [0],
      );
      expect(play(state, 0).currentSeat, 0);
    });
  });
}
