import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _banked = RulesConfig(bankedRolls: true);

/// Seat 0: tokens at 10 and 20; seat 1: one token on absolute square 14, which
/// a 4 from seat 0's token at 10 captures.
GameState _board({RulesConfig rules = _banked}) => makeState(
      rules: rules,
      tokens: {
        0: [10, 20, -1, -1],
        1: [relativeFor(1, 14), -1, -1, -1],
      },
    );

/// Seat 0's only live token is at 46; seat 1's token on absolute square 50 is
/// captured by a 4. Afterwards the token at 50 can absorb at most one die.
GameState _captureBoard() => makeState(
      rules: _banked,
      tokens: {
        0: [46, 56, 56, 56],
        1: [relativeFor(1, 50), -1, -1, -1],
      },
    );

GameState _spend(GameState state, int token, int value) {
  final move = Engine.legalMoves(state).firstWhere(
    (m) => m.tokenIndex == token && state.bank[m.dieIndex] == value,
    orElse: () => throw StateError('No legal $value for token $token'),
  );
  return Engine.apply(state, move);
}

GameState _spendAny(GameState state, int value) {
  final move = Engine.legalMoves(state).firstWhere(
    (m) => state.bank[m.dieIndex] == value,
    orElse: () => throw StateError('No legal $value'),
  );
  return Engine.apply(state, move);
}

List<RollOutcome> _outcomes(List<RollResult> results) =>
    [for (final r in results) r.outcome];

void main() {
  group('rolling phase (Roll All First)', () {
    test('a 6 is banked and rolls again, without moving anything', () {
      final board = _board();
      final results = rollSequence(board, [6]);
      final state = results.single.state;
      expect(results.single.outcome, RollOutcome.banked);
      expect(state.bank, [6]);
      expect(state.awaitingRoll, isTrue);
      expect(state.awaitingMove, isFalse);
      expect(state.dice, isNull);
      expect(state.consecutiveSixes, 1);
      expect(state.currentSeat, 0);
      expect(state.tokens, board.tokens);
    });

    test('a 1-5 ends the sequence and starts the moving phase', () {
      final results = rollSequence(_board(), [6, 3]);
      expect(
          _outcomes(results), [RollOutcome.banked, RollOutcome.awaitingMove]);
      final state = results.last.state;
      expect(state.bank, [6, 3]);
      expect(state.bankPhase, BankPhase.moving);
      expect(state.awaitingMove, isTrue);
      expect(state.consecutiveSixes, 0);
      expect(state.turnSnapshot, isNotNull);
      expect(state.turnSnapshot!.bank, [6, 3]);
      expect(state.turnSnapshot!.tokens, _board().tokens);
      expect(() => Engine.roll(state), throwsStateError);
    });

    test('a lone 1-5 ends the sequence at once', () {
      final results = rollSequence(_board(), [4]);
      expect(results.single.outcome, RollOutcome.awaitingMove);
      expect(results.single.state.bank, [4]);
    });

    test('three 6s wipe the whole bank and forfeit the turn', () {
      final board = _board();
      final results = rollSequence(board, [6, 6, 6]);
      expect(_outcomes(results), [
        RollOutcome.banked,
        RollOutcome.banked,
        RollOutcome.tripleSixForfeit,
      ]);
      final state = results.last.state;
      expect(state.bank, isEmpty);
      expect(state.currentSeat, 1);
      expect(state.turnNumber, 1);
      expect(state.turnSnapshot, isNull);
      expect(state.bankPhase, BankPhase.rolling);
      expect(state.consecutiveSixes, 0);
      expect(state.tokens, board.tokens);
    });

    test('two 6s then a 1-5 is not a forfeit', () {
      final results = rollSequence(_board(), [6, 6, 5]);
      expect(results.last.outcome, RollOutcome.awaitingMove);
      expect(results.last.state.bank, [6, 6, 5]);
    });

    test('without tripleSixForfeit sixes keep banking', () {
      final board = _board(rules: _banked.copyWith(tripleSixForfeit: false));
      final results = rollSequence(board, [6, 6, 6, 6]);
      expect(results.every((r) => r.outcome == RollOutcome.banked), isTrue);
      expect(results.last.state.bank, [6, 6, 6, 6]);
    });

    test('without extraTurnOnSix a 6 ends the sequence like a 1-5', () {
      final board = _board(rules: _banked.copyWith(extraTurnOnSix: false));
      final results = rollSequence(board, [6]);
      expect(results.single.outcome, RollOutcome.awaitingMove);
      expect(results.single.state.bank, [6]);
    });
  });

  group('moving phase', () {
    test('legal moves name the die by its index, one per distinct value', () {
      final state = rollSequence(_board(), [6, 6, 4]).last.state;
      final moves = Engine.legalMoves(state);
      expect(moves.map((m) => state.bank[m.dieIndex]).toSet(), {6, 4});
      expect(moves.map((m) => m.dieIndex).toSet(), {0, 2});
      expect(
        moves.where((m) => state.bank[m.dieIndex] == 4).map((m) => m.to),
        unorderedEquals([14, 24]),
      );
    });

    test('dice can be spent in any order across any tokens', () {
      const tokens = {
        0: [10, 20, -1, -1],
      };
      final start = makeMoving(bank: [6, 6, 4], tokens: tokens);

      // 4 first, then both sixes on token 1.
      var a = _spend(start, 0, 4);
      expect(a.bank, [6, 6]);
      expect(a.currentSeat, 0);
      a = _spend(a, 1, 6);
      a = _spend(a, 1, 6);

      // Both sixes first, then the 4.
      var b = _spend(start, 1, 6);
      b = _spend(b, 1, 6);
      b = _spend(b, 0, 4);

      for (final end in [a, b]) {
        expect(end.tokens[0], [14, 32, -1, -1]);
        expect(end.bank, isEmpty);
        expect(end.currentSeat, 1);
      }
      expect(a, b);
    });

    test('any index holding an equal value spends the same die', () {
      final start = makeMoving(
        bank: [6, 6, 4],
        tokens: {
          0: [10, 20, -1, -1],
        },
      );
      final viaSecond = Engine.apply(
        start,
        const Move(owner: 0, tokenIndex: 0, from: 10, to: 16, dieIndex: 1),
      );
      final viaFirst = Engine.apply(
        start,
        const Move(owner: 0, tokenIndex: 0, from: 10, to: 16, dieIndex: 0),
      );
      expect(viaSecond, viaFirst);
      expect(viaSecond.bank, [6, 4]);
    });

    test('only moves that leave the rest of the bank spendable are legal', () {
      // All tokens in the yard: the 3 can only be spent after a 6 exits.
      final state = makeMoving(bank: [6, 3]);
      final moves = Engine.legalMoves(state);
      expect(moves, isNotEmpty);
      expect(moves.every((m) => state.bank[m.dieIndex] == 6), isTrue);
      final after = _spend(state, 0, 6);
      expect(
        Engine.legalMoves(after).map((m) => (m.tokenIndex, m.to)),
        [(0, 3)],
      );
    });

    test('no moves outside the moving phase', () {
      final rolling = _board();
      expect(Engine.legalMoves(rolling), isEmpty);
      expect(
        () => Engine.apply(
          rolling,
          const Move(owner: 0, tokenIndex: 0, from: 10, to: 14),
        ),
        throwsA(isA<IllegalMoveException>()),
      );
    });

    test('the move log records the spent value and replays', () {
      final start = makeMoving(
        bank: [6, 4],
        tokens: {
          0: [10, -1, -1, -1],
        },
      );
      final move = Engine.legalMoves(start)
          .firstWhere((m) => start.bank[m.dieIndex] == 4);
      final entry = Engine.logEntry(start, move);
      expect(entry.dice, 4);
      expect(Engine.applyEntry(start, entry), Engine.apply(start, move));
    });
  });

  group('all-or-nothing', () {
    test('a bank that cannot be spent in full is forfeited from the start', () {
      final board = makeState(
        rules: _banked,
        tokens: {
          0: [54, 56, 56, 56],
        },
      );
      // 2 finishes the token but the 6 can never be spent.
      final results = rollSequence(board, [6, 2]);
      expect(_outcomes(results), [RollOutcome.banked, RollOutcome.bankDeadEnd]);
      final state = results.last.state;
      expect(state.tokens, board.tokens);
      expect(state.bank, isEmpty);
      expect(state.currentSeat, 1);
      expect(state.awaitingRoll, isTrue);
      expect(state.turnSnapshot, isNull);
    });

    /// Seat 0 captures with a lone 4, leaving the bonus sequence to roll.
    GameState captured() {
      final moving = rollSequence(_captureBoard(), [4]).single.state;
      final after = _spend(moving, 0, 4);
      expect(after.tokens[0][0], 50);
      expect(after.tokens[1][0], -1);
      expect(after.bankPhase, BankPhase.rolling);
      expect(after.bank, isEmpty);
      expect(after.currentSeat, 0);
      return after;
    }

    test('a dead end after a bonus roll reverts the whole turn', () {
      final results = rollSequence(captured(), [6, 6, 3]);
      expect(_outcomes(results), [
        RollOutcome.banked,
        RollOutcome.banked,
        RollOutcome.bankDeadEnd,
      ]);
      final state = results.last.state;
      // The capture is undone along with every other move of the turn.
      expect(state.tokens, _captureBoard().tokens);
      expect(state.bank, isEmpty);
      expect(state.currentSeat, 1);
      expect(state.turnSnapshot, isNull);
    });

    test('a triple six in a bonus sequence keeps the moves made', () {
      final results = rollSequence(captured(), [6, 6, 6]);
      expect(_outcomes(results), [
        RollOutcome.banked,
        RollOutcome.banked,
        RollOutcome.tripleSixForfeit,
      ]);
      final state = results.last.state;
      expect(state.tokens[0][0], 50);
      expect(state.tokens[1][0], -1);
      expect(state.bank, isEmpty);
      expect(state.currentSeat, 1);
      expect(state.turnSnapshot, isNull);
    });

    test('a move that ends the match is legal only as the last die', () {
      const firstToWin = RulesConfig(
        bankedRolls: true,
        endMode: EndMode.firstToWin,
      );
      const tokens = {
        0: [56, 56, 56, 55],
      };
      // Winning with the 1 would strand the 3: dead end, no legal move.
      expect(
        Engine.legalMoves(
          makeMoving(bank: [1, 3], rules: firstToWin, tokens: tokens),
        ),
        isEmpty,
      );
      final last = makeMoving(bank: [1], rules: firstToWin, tokens: tokens);
      final won = _spendAny(last, 1);
      expect(won.isOver, isTrue);
      expect(won.bank, isEmpty);
      expect(won.turnSnapshot, isNull);
    });
  });

  group('bonus sequences', () {
    /// Bank 6,6,4 with a 4 that captures; after the capture the bank is 6,6
    /// and the bonus sequence is due.
    GameState afterCapture() {
      final moving = rollSequence(_board(), [6, 6, 4]).last.state;
      expect(moving.bank, [6, 6, 4]);
      final after = _spend(moving, 0, 4);
      expect(after.tokens[1][0], -1);
      expect(after.bankPhase, BankPhase.rolling);
      expect(after.bank, [6, 6]);
      expect(after.consecutiveSixes, 0);
      expect(after.currentSeat, 0);
      return after;
    }

    test('bonus dice are added to the remaining bank (6,6,x example)', () {
      final results = rollSequence(afterCapture(), [6, 6, 2]);
      expect(_outcomes(results), [
        RollOutcome.banked,
        RollOutcome.banked,
        RollOutcome.awaitingMove,
      ]);
      final state = results.last.state;
      expect(state.bank, [6, 6, 6, 6, 2]);
      expect(state.bankPhase, BankPhase.moving);
      expect(state.currentSeat, 0);
      expect(Engine.legalMoves(state), isNotEmpty);
    });

    test('older 6s in the bank do not count toward the bonus sequence', () {
      final results = rollSequence(afterCapture(), [6, 6, 6]);
      // Two bank sixes + the first two bonus sixes would already be four.
      expect(_outcomes(results), [
        RollOutcome.banked,
        RollOutcome.banked,
        RollOutcome.tripleSixForfeit,
      ]);
      final state = results.last.state;
      expect(state.bank, isEmpty);
      expect(state.currentSeat, 1);
      // Moves already made (the capture) are kept.
      expect(state.tokens[0][0], 14);
      expect(state.tokens[1][0], -1);
    });

    test('the counter starts at 0 for each bonus sequence', () {
      final after = afterCapture();
      expect(after.consecutiveSixes, 0);
      final results = rollSequence(after, [6, 6, 5]);
      expect(results[1].state.consecutiveSixes, 2);
      expect(results.last.state.consecutiveSixes, 0);
      expect(results.last.state.bank, [6, 6, 6, 6, 5]);
    });

    test('several captures and home moves each grant their own sequence', () {
      final board = makeState(
        rules: _banked,
        tokens: {
          0: [10, 30, -1, -1],
          1: [relativeFor(1, 14), -1, -1, -1],
          2: [relativeFor(2, 36), -1, -1, -1],
        },
      );
      var state = rollSequence(board, [6, 4]).last.state;
      expect(state.bank, [6, 4]);

      // First capture (4) -> first bonus sequence.
      state = _spend(state, 0, 4);
      expect(state.bankPhase, BankPhase.rolling);
      expect(state.bank, [6]);
      state = rollSequence(state, [3]).single.state;
      expect(state.bank, [6, 3]);

      // Second capture (6) -> second bonus sequence.
      state = _spend(state, 1, 6);
      expect(state.tokens[2][0], -1);
      expect(state.bankPhase, BankPhase.rolling);
      expect(state.bank, [3]);
      expect(state.consecutiveSixes, 0);
      state = rollSequence(state, [2]).single.state;
      expect(state.bank, [3, 2]);
      expect(state.currentSeat, 0);
      expect(state.turnNumber, 0);

      state = _spendAny(state, 3);
      state = _spendAny(state, 2);
      expect(state.currentSeat, 1);
      expect(state.turnNumber, 1);
    });

    test('reaching home grants a bonus sequence', () {
      final moving = makeMoving(
        bank: [2, 5],
        tokens: {
          0: [54, 40, -1, -1],
        },
      );
      final after = _spend(moving, 0, 2);
      expect(after.tokens[0][0], 56);
      expect(after.bankPhase, BankPhase.rolling);
      expect(after.bank, [5]);
    });

    test('extraTurnOnCapture: false grants no bonus sequence', () {
      final rules = _banked.copyWith(extraTurnOnCapture: false);
      final moving = rollSequence(_board(rules: rules), [4]).single.state;
      final after = _spend(moving, 0, 4);
      expect(after.tokens[1][0], -1);
      expect(after.currentSeat, 1);
      expect(after.bank, isEmpty);
    });
  });

  group('bank lifecycle', () {
    test('the bank is cleared when the turn passes', () {
      var state = rollSequence(_board(), [6, 3]).last.state;
      expect(state.bankOf(0), [6, 3]);
      state = _spend(state, 1, 6);
      state = _spend(state, 1, 3);
      expect(state.currentSeat, 1);
      expect(state.turnNumber, 1);
      expect(state.bank, isEmpty);
      expect(state.bankOf(0), isEmpty);
      expect(state.bankOf(1), isEmpty);
      expect(state.bankPhase, BankPhase.rolling);
      expect(state.turnSnapshot, isNull);
      expect(state.awaitingRoll, isTrue);
    });

    test('nextDecision rolls through a whole rolling sequence', () {
      final state = Engine.nextDecision(withDice(_board(), [6, 6, 2]));
      expect(state.awaitingMove, isTrue);
      expect(state.bank, [6, 6, 2]);
    });

    test('states differ by bank, phase and snapshot', () {
      final a = makeMoving(bank: [6, 3]);
      expect(a, makeMoving(bank: [6, 3]));
      expect(a.hashCode, makeMoving(bank: [6, 3]).hashCode);
      expect(a == makeMoving(bank: [6, 2]), isFalse);
      expect(a == a.copyWith(bankPhase: BankPhase.rolling), isFalse);
      expect(a == a.copyWith(clearSnapshot: true), isFalse);
    });
  });

  group('bankedRolls: false (classic behaviour unchanged)', () {
    test('is off by default and in every preset', () {
      expect(const RulesConfig().bankedRolls, isFalse);
      expect(const RulesConfig.classic().bankedRolls, isFalse);
      expect(const RulesConfig.quick().bankedRolls, isFalse);
      expect(const RulesConfig.strategic().bankedRolls, isFalse);
      expect(
          const RulesConfig().copyWith(bankedRolls: true).bankedRolls, isTrue);
    });

    test('a roll sets the single pending die and never touches the bank', () {
      final board = _board(rules: const RulesConfig());
      final result = rollSequence(board, [6]).single;
      expect(result.outcome, RollOutcome.awaitingMove);
      expect(result.state.dice, 6);
      expect(result.state.bank, isEmpty);
      expect(result.state.bankPhase, BankPhase.rolling);
      expect(result.state.turnSnapshot, isNull);
      final moves = Engine.legalMoves(result.state);
      expect(moves.every((m) => m.dieIndex == 0), isTrue);
    });

    test('three 6s still forfeit only the turn, not a bank', () {
      final board = _board(rules: const RulesConfig());
      var state = board.copyWith(rngState: findRngState([6]));
      state = Engine.roll(state).state;
      state = play(state, 0); // 10 -> 16, bonus turn for the 6
      state = state.copyWith(rngState: findRngState([6]));
      state = Engine.roll(state).state;
      state = play(state, 0);
      state = state.copyWith(rngState: findRngState([6]));
      final third = Engine.roll(state);
      expect(third.outcome, RollOutcome.tripleSixForfeit);
      expect(third.state.currentSeat, 1);
      expect(third.state.bank, isEmpty);
    });
  });
}
