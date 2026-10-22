import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The optional blockade rules (docs/ludo-rules.md section 9).
void main() {
  const base = RulesConfig(blockades: true);

  /// Legal moves of the controlled seat for [dice].
  List<Move> moves(GameState state, int dice) => Engine.legalMoves(state, dice);

  /// Moves that start on the track (a six also lets yard tokens out).
  List<Move> trackMoves(GameState state, int dice) =>
      moves(state, dice).where((m) => m.from != yardPosition).toList();

  List<Move> units(GameState state, int dice) =>
      moves(state, dice).where((m) => m.isUnit).toList();

  List<Move> singles(GameState state, int dice) =>
      moves(state, dice).where((m) => !m.isUnit).toList();

  Move unitMove(GameState state) =>
      Engine.legalMoves(state).singleWhere((m) => m.isUnit);

  group('option prerequisites', () {
    test('everything is off by default', () {
      const rules = RulesConfig();
      expect(rules.blockadeFriendlyRestriction, isFalse);
      expect(rules.blockadeMovement, isFalse);
      expect(rules.blockadeCapture, isFalse);
      expect(rules.blockadeUnbreakable, isFalse);
      expect(rules.pieceOnBlockade, isFalse);
    });

    test('without blockades no option is in force', () {
      const rules = RulesConfig(
        blockadeFriendlyRestriction: true,
        blockadeMovement: true,
        blockadeCapture: true,
        blockadeUnbreakable: true,
        pieceOnBlockade: true,
      );
      expect(rules.friendlyRestrictionActive, isFalse);
      expect(rules.blockadeMovementActive, isFalse);
      expect(rules.blockadeCaptureActive, isFalse);
      expect(rules.blockadeUnbreakableActive, isFalse);
      expect(rules.pieceOnBlockadeActive, isFalse);
      expect(rules.normalized(), const RulesConfig());
    });

    test('capture and unbreakable need blockade movement', () {
      const rules = RulesConfig(
        blockades: true,
        blockadeCapture: true,
        blockadeUnbreakable: true,
        pieceOnBlockade: true,
      );
      expect(rules.blockadeCaptureActive, isFalse);
      expect(rules.blockadeUnbreakableActive, isFalse);
      expect(rules.pieceOnBlockadeActive, isTrue);
      final fixed = rules.normalized();
      expect(fixed.blockadeCapture, isFalse);
      expect(fixed.blockadeUnbreakable, isFalse);
      expect(fixed.pieceOnBlockade, isTrue);

      final withMovement = rules.copyWith(blockadeMovement: true);
      expect(withMovement.blockadeCaptureActive, isTrue);
      expect(withMovement.blockadeUnbreakableActive, isTrue);
      expect(withMovement.normalized(), withMovement);
    });

    test('equality and hashing include the options', () {
      const a = RulesConfig(blockades: true, blockadeMovement: true);
      const b = RulesConfig(blockades: true, blockadeMovement: true);
      const c = RulesConfig(blockades: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('safe squares are part of the blockade rule', () {
    // Seat 1's pair on the star square 8 (relative 47 for seat 1).
    GameState pairOn(int square, {int seat = 1}) => makeState(
          rules: base,
          tokens: {
            0: [5, -1, -1, -1],
            seat: [
              relativeFor(seat, square),
              relativeFor(seat, square),
              -1,
              -1
            ],
          },
        );

    test('a pair on a safe square blocks nobody', () {
      expect(moves(pairOn(8), 4), hasLength(1)); // passes it
      final landed = Engine.apply(
        pairOn(8).copyWith(dice: 3),
        moves(pairOn(8), 3).single,
      );
      // Safe square: coexistence, nobody is captured.
      expect(landed.tokens[0][0], 8);
      expect(landed.tokens[1].take(2), everyElement(relativeFor(1, 8)));
    });

    test('a pair on a start square of another seat blocks nobody either', () {
      // Square 13 is seat 1's start square; seat 2's pair is no blockade.
      final state = makeState(
        rules: base,
        tokens: {
          0: [10, -1, -1, -1],
          2: [relativeFor(2, 13), relativeFor(2, 13), -1, -1],
        },
      );
      expect(moves(state, 4), hasLength(1));
    });

    test('a pair on its owner\'s own start square is a blockade', () {
      final state = makeState(
        rules: base,
        tokens: {
          0: [10, -1, -1, -1],
          1: [0, 0, -1, -1], // square 13
        },
      );
      expect(moves(state, 3), isEmpty);
      expect(moves(state, 5), isEmpty);
      expect(moves(state, 2), hasLength(1));
    });

    test('a pair on an ordinary square blocks', () {
      expect(moves(pairOn(9), 4), isEmpty);
    });
  });

  group('friendly blockade restriction', () {
    GameState ownPair(RulesConfig rules) => makeState(
          rules: rules,
          tokens: {
            0: [7, 10, 10, -1],
          },
        );

    test('by default you pass your own blockade', () {
      expect(canMove(ownPair(base), 0, 5), isTrue);
    });

    test('with the option you cannot pass your own blockade', () {
      final rules = base.copyWith(blockadeFriendlyRestriction: true);
      final state = ownPair(rules);
      expect(canMove(state, 0, 5), isFalse); // 7 -> 12 passes 10
      expect(canMove(state, 0, 3), isTrue); // landing on it is allowed
    });

    test('the tokens of the blockade itself are not held back', () {
      final rules = base.copyWith(blockadeFriendlyRestriction: true);
      expect(canMove(ownPair(rules), 1, 3), isTrue);
    });

    test('teammates cannot pass it either', () {
      final teams = base.copyWith(blockadeFriendlyRestriction: true).copyWith(
            teamsEnabled: true,
          );
      final state = makeState(
        rules: teams,
        tokens: {
          0: [7, -1, -1, -1],
          2: [relativeFor(2, 10), relativeFor(2, 10), -1, -1],
        },
      );
      expect(moves(state, 5), isEmpty);
      final open = state.copyWith(
        tokens: state.tokens,
      );
      final without = makeState(
        rules: base.copyWith(teamsEnabled: true),
        tokens: {
          0: [7, -1, -1, -1],
          2: [relativeFor(2, 10), relativeFor(2, 10), -1, -1],
        },
      );
      expect(open.rules.friendlyRestrictionActive, isTrue);
      expect(moves(without, 5), hasLength(1));
    });

    test('opponent blockades are unaffected (still impassable)', () {
      final rules = base.copyWith(blockadeFriendlyRestriction: true);
      final state = makeState(
        rules: rules,
        tokens: {
          0: [7, -1, -1, -1],
          1: [relativeFor(1, 10), relativeFor(1, 10), -1, -1],
        },
      );
      expect(moves(state, 5), isEmpty);
    });
  });

  group('blockade movement', () {
    final rules = base.copyWith(blockadeMovement: true);

    GameState pairAt(int p, {RulesConfig? r, Map<int, List<int>>? more}) =>
        makeState(
          rules: r ?? rules,
          tokens: {
            0: [p, p, -1, -1],
            ...?more,
          },
        );

    test('a pair moves as a unit on an even roll, half the roll each', () {
      final state = pairAt(10).copyWith(dice: 4);
      final move = unitMove(state);
      expect(move.tokenIndex, 0);
      expect(move.partnerIndex, 1);
      expect(move.to, 12);
      final after = Engine.apply(state, move);
      expect(after.tokens[0].take(2), [12, 12]);
    });

    test('odd rolls give no unit move', () {
      for (final d in [1, 3, 5]) {
        expect(units(pairAt(10), d), isEmpty, reason: 'roll $d');
      }
      for (final d in [2, 4, 6]) {
        expect(units(pairAt(10), d), hasLength(1), reason: 'roll $d');
      }
    });

    test('the single-token moves stay available (the pair may be split)', () {
      final state = pairAt(10);
      expect(singles(state, 4), hasLength(2));
      final split = Engine.apply(
        state.copyWith(dice: 4),
        singles(state, 4).first,
      );
      expect(split.tokens[0].take(2), [14, 10]);
    });

    test('only exactly two tokens form a movable blockade', () {
      final three = makeState(
        rules: rules,
        tokens: {
          0: [10, 10, 10, -1],
        },
      );
      expect(units(three, 4), isEmpty);
      final apart = makeState(
        rules: rules,
        tokens: {
          0: [10, 11, -1, -1],
        },
      );
      expect(units(apart, 4), isEmpty);
    });

    test('a moving blockade jumps over other blockades', () {
      final state = pairAt(
        10,
        more: {
          1: [relativeFor(1, 11), relativeFor(1, 11), -1, -1],
        },
      );
      expect(units(state, 4), hasLength(1)); // 10 -> 12 over the block on 11
      expect(singles(state, 4), isEmpty); // a single token cannot
    });

    test('it jumps over friendly blockades even when they are restricted', () {
      final strict = rules.copyWith(blockadeFriendlyRestriction: true);
      final state = makeState(
        rules: strict,
        tokens: {
          0: [10, 10, 11, 11],
        },
      );
      expect(units(state, 4).where((m) => m.from == 10), hasLength(1));
    });

    test('it cannot land on an opponent blockade without blockade capture', () {
      final state = pairAt(
        10,
        more: {
          2: [relativeFor(2, 12), relativeFor(2, 12), -1, -1],
        },
      );
      expect(units(state, 4), isEmpty);
    });

    test('it cannot land on a blockade of its own', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [10, 10, 12, 12],
        },
      );
      expect(units(state, 4).where((m) => m.from == 10), isEmpty);
    });

    test('a blockade can walk into the home column (and ends there)', () {
      expect(units(pairAt(50), 2).single.to, 51);
      expect(units(pairAt(50), 6).single.to, 53);
      // In the home column a pair is no blockade any more.
      final inside = makeState(
        rules: rules,
        tokens: {
          0: [53, 53, -1, -1],
        },
      );
      expect(units(inside, 2), isEmpty);
    });

    test('a pair on a safe square is no blockade, so it cannot move as one',
        () {
      expect(units(pairAt(8), 4), isEmpty);
    });

    test('a pair on its own start square is a blockade and can move', () {
      expect(units(pairAt(0), 4), hasLength(1));
    });

    test('it never captures a single piece, so it cannot land on one', () {
      final state = pairAt(
        10,
        more: {
          2: [relativeFor(2, 12), -1, -1, -1],
        },
      );
      expect(units(state, 4), isEmpty);
      // The single token could capture it, as always.
      expect(singles(state, 2), hasLength(2));
    });

    test('on a safe square it may share with a single piece, no capture', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [6, 6, -1, -1],
          2: [relativeFor(2, 8), -1, -1, -1],
        },
        dice: 4,
      );
      final after = Engine.apply(state, unitMove(state));
      expect(after.tokens[0].take(2), [8, 8]);
      expect(after.tokens[2][0], relativeFor(2, 8));
    });

    test('the option is inert without the blockades switch', () {
      const off = RulesConfig(blockadeMovement: true);
      expect(units(pairAt(10, r: off), 4), isEmpty);
    });

    test('the move log replays unit moves', () {
      final state = pairAt(10);
      final ready = state.copyWith(dice: 4);
      final move = unitMove(ready);
      final entry = Engine.logEntry(ready, move);
      expect(entry.unit, isTrue);
      expect(entry.tokenIndex, 0);
      final replayed = Engine.applyEntry(ready, entry);
      expect(replayed.tokens[0].take(2), [12, 12]);
      // The same token as a single move is a different entry.
      final single = Engine.logEntry(ready, singles(ready, 4).first);
      expect(single.unit, isFalse);
      expect(single, isNot(entry));
    });

    test('a forged unit move is rejected when no blockade stands there', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [10, 11, -1, -1],
        },
        dice: 4,
      );
      expect(
        () => Engine.apply(
          state,
          const Move(
            owner: 0,
            tokenIndex: 0,
            from: 10,
            to: 12,
            partnerIndex: 1,
          ),
        ),
        throwsA(isA<IllegalMoveException>()),
      );
    });
  });

  group('blockade capture', () {
    final rules = base.copyWith(
      blockadeMovement: true,
      blockadeCapture: true,
    );

    GameState duel(int square, {RulesConfig? r}) => makeState(
          rules: r ?? rules,
          tokens: {
            0: [10, 10, -1, -1],
            2: [relativeFor(2, square), relativeFor(2, square), -1, -1],
          },
        );

    test('a moving blockade captures an opponent blockade', () {
      final state = duel(12).copyWith(dice: 4);
      final move = unitMove(state);
      final after = Engine.apply(state, move);
      expect(after.tokens[2].take(2), [yardPosition, yardPosition]);
      expect(after.tokens[0].take(2), [12, 12]);
      expect(after.currentSeat, 0); // a capture earns the bonus turn
    });

    test('without the option the same move is illegal', () {
      final off = base.copyWith(blockadeMovement: true);
      expect(units(duel(12, r: off), 4), isEmpty);
    });

    test(
        'on a safe square an opposing pair is no blockade: shared, not '
        'captured', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [6, 6, -1, -1],
          2: [relativeFor(2, 8), relativeFor(2, 8), -1, -1],
        },
        dice: 4,
      );
      final after = Engine.apply(state, unitMove(state));
      expect(after.tokens[0].take(2), [8, 8]);
      expect(after.tokens[2].take(2), everyElement(relativeFor(2, 8)));
    });

    test('a blockade on its owner\'s start square is safe from capture', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [10, 10, -1, -1],
          1: [0, 0, -1, -1], // square 13
        },
      );
      expect(units(state, 6), isEmpty); // 10 + 3 = 13
    });

    test('single tokens still cannot capture a blockade', () {
      expect(singles(duel(12), 2), isEmpty); // landing on it
      expect(singles(duel(12), 4), isEmpty);
    });

    test('a teammate blockade is not captured and not landed on', () {
      final teams = rules.copyWith(teamsEnabled: true);
      final state = makeState(
        rules: teams,
        tokens: {
          0: [10, 10, -1, -1],
          2: [relativeFor(2, 12), relativeFor(2, 12), -1, -1],
        },
      );
      expect(units(state, 4), isEmpty);
    });

    test('is inert without blockade movement', () {
      const noMove = RulesConfig(blockades: true, blockadeCapture: true);
      expect(units(duel(12, r: noMove), 4), isEmpty);
    });
  });

  group('unbreakable blockade', () {
    final rules = base.copyWith(
      blockadeMovement: true,
      blockadeUnbreakable: true,
    );

    test('the two tokens only move together', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [10, 10, -1, -1],
        },
      );
      expect(singles(state, 4), isEmpty);
      expect(units(state, 4), hasLength(1));
    });

    test('so odd rolls leave the pair standing', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [10, 10, -1, -1],
        },
      );
      for (final d in [1, 3, 5]) {
        expect(moves(state, d), isEmpty, reason: 'roll $d');
      }
    });

    test('other tokens are free to move', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [10, 10, 20, -1],
        },
      );
      expect(singles(state, 3).map((m) => m.tokenIndex), [2]);
    });

    test('on a safe square the pair may be split', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [8, 8, -1, -1],
        },
      );
      expect(singles(state, 3), hasLength(2));
    });

    test('a stack of three may lose one token', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [10, 10, 10, -1],
        },
      );
      expect(singles(state, 3), hasLength(3));
    });

    test('a pair that reached a safe square can split afterwards', () {
      final state = makeState(
        rules: rules,
        tokens: {
          0: [6, 6, -1, -1],
        },
        dice: 4,
      );
      final onStar = Engine.apply(state, unitMove(state));
      expect(onStar.tokens[0].take(2), [8, 8]);
      final next = onStar.copyWith(currentSeat: 0, dice: 3);
      expect(singles(next, 3), hasLength(2));
    });

    test('is inert without blockade movement', () {
      const noMove = RulesConfig(blockades: true, blockadeUnbreakable: true);
      final state = makeState(
        rules: noMove,
        tokens: {
          0: [10, 10, -1, -1],
        },
      );
      expect(singles(state, 3), hasLength(2));
    });
  });

  group('piece on blockade', () {
    final rules = base.copyWith(pieceOnBlockade: true);

    // Seat 0 token at 5 (and another at 8); seat 1 pair on the ordinary
    // square 11, six squares ahead of the first token.
    GameState siege({RulesConfig? r, List<int>? mine}) => makeState(
          rules: r ?? rules,
          tokens: {
            0: mine ?? [5, 8, -1, -1],
            1: [relativeFor(1, 11), relativeFor(1, 11), relativeFor(1, 5), -1],
          },
        );

    test('by default nobody lands on an opponent blockade', () {
      expect(trackMoves(siege(r: base), 6), isEmpty);
    });

    test('with the option a single piece may land there', () {
      expect(trackMoves(siege(), 6).map((m) => m.tokenIndex), [0]);
    });

    test('passing the blockade is still impossible', () {
      // Token 1 (8 -> 14) would pass square 11.
      expect(canMove(siege(), 1, 6), isFalse);
    });

    test('landing captures nothing; the piece waits out the rest of the turn',
        () {
      final state = siege(mine: [5, -1, -1, -1]).copyWith(dice: 6);
      final after = Engine.apply(state, trackMoves(state, 6).single);
      expect(after.tokens[0][0], 11);
      expect(after.tokens[1].take(2), everyElement(relativeFor(1, 11)));
      // The six earns another roll, in which the piece cannot move.
      expect(after.currentSeat, 0);
      expect(after.rest[0][0], 1);
      expect(after.isWaiting(0, 0), isTrue);
      expect(canMove(after.copyWith(dice: 3), 0), isFalse);
    });

    test('and is free to move on its owner\'s very next turn', () {
      final state = siege(mine: [5, -1, -1, -1]).copyWith(dice: 6);
      final landed = Engine.apply(state, trackMoves(state, 6).single);
      // The extra roll finds nothing to move: the turn ends, the wait ends.
      final extra = Engine.roll(
        landed.copyWith(rngState: findRngState([3])),
      );
      expect(extra.outcome, RollOutcome.noLegalMoves);
      expect(extra.state.rest[0][0], 0);
      // Seat 0's next turn: the piece moves.
      final next = extra.state.copyWith(currentSeat: 0, dice: 3);
      expect(canMove(next, 0), isTrue);
    });

    test('without a bonus roll it is free on the next turn at once', () {
      // A four lands on 9 (ordinary square), no extra turn.
      final state = makeState(
        rules: rules,
        tokens: {
          0: [5, -1, -1, -1],
          1: [relativeFor(1, 9), relativeFor(1, 9), -1, -1],
        },
        dice: 4,
      );
      final after = Engine.apply(state, moves(state, 4).single);
      expect(after.tokens[0][0], 9);
      expect(after.rest[0][0], 0);
      expect(canMove(after.copyWith(currentSeat: 0, dice: 3), 0), isTrue);
    });

    test('a waiting piece cannot move', () {
      final waiting = makeState(
        rules: rules,
        tokens: {
          0: [9, 20, -1, -1],
        },
        rest: {
          0: [1, 0, 0, 0],
        },
      );
      expect(canMove(waiting, 0, 3), isFalse);
      expect(canMove(waiting, 1, 3), isTrue);
    });

    test('the blockade owner captures the squatter with a single token', () {
      // Seat 0 sits on seat 1's blockade at 9; seat 1's third token (at
      // relative 44, absolute 5) lands there with a 4.
      final state = makeState(
        rules: rules,
        tokens: {
          0: [9, -1, -1, -1],
          1: [relativeFor(1, 9), relativeFor(1, 9), relativeFor(1, 5), -1],
        },
        rest: {
          0: [1, 0, 0, 0],
        },
        currentSeat: 1,
        dice: 4,
      );
      final capture = moves(state, 4).singleWhere((m) => m.tokenIndex == 2);
      final after = Engine.apply(state, capture);
      expect(after.tokens[0][0], yardPosition);
      expect(after.rest[0][0], 0);
      expect(after.tokens[1].take(3), everyElement(relativeFor(1, 9)));
    });

    test('a blockade can walk away and leave the squatter behind', () {
      final moving = rules.copyWith(blockadeMovement: true);
      final state = makeState(
        rules: moving,
        tokens: {
          0: [9, -1, -1, -1],
          1: [relativeFor(1, 9), relativeFor(1, 9), -1, -1],
        },
        currentSeat: 1,
        dice: 2,
      );
      final after = Engine.apply(state, unitMove(state));
      expect(after.tokens[1].take(2), everyElement(relativeFor(1, 10)));
      expect(after.tokens[0][0], 9); // left behind, alone and capturable
    });

    test('a pair on its owner\'s start square can be squatted on too', () {
      // Seat 1's start square is 13; seat 0 lands on it with a 3.
      final state = makeState(
        rules: rules,
        tokens: {
          0: [10, -1, -1, -1],
          1: [0, 0, -1, -1],
        },
        dice: 3,
      );
      final after = Engine.apply(state, moves(state, 3).single);
      expect(after.tokens[0][0], 13);
      expect(after.tokens[1].take(2), [0, 0]);
    });

    test('a teammate blockade is not squatted on', () {
      final teams = rules.copyWith(teamsEnabled: true);
      final state = makeState(
        rules: teams,
        tokens: {
          0: [5, -1, -1, -1],
          2: [relativeFor(2, 9), relativeFor(2, 9), -1, -1],
        },
      );
      expect(moves(state, 4), isEmpty);
    });

    test('is inert without the blockades switch', () {
      const off = RulesConfig(pieceOnBlockade: true);
      expect(off.pieceOnBlockadeActive, isFalse);
    });

    test('banked: the wait is part of the turn state and is restored', () {
      final banked = rules.copyWith(bankedRolls: true);
      final start = makeMoving(
        rules: banked,
        bank: [4],
        tokens: {
          0: [5, -1, -1, -1],
          1: [relativeFor(1, 9), relativeFor(1, 9), -1, -1],
        },
      );
      final after = Engine.apply(start, Engine.legalMoves(start).single);
      expect(after.tokens[0][0], 9);
      expect(after.rest[0][0], 0); // turn over: free next turn
      expect(start.rest[0][0], 0); // the old state is untouched
    });
  });

  group('everything together', () {
    const all = RulesConfig(
      blockades: true,
      blockadeFriendlyRestriction: true,
      blockadeMovement: true,
      blockadeCapture: true,
      blockadeUnbreakable: true,
      pieceOnBlockade: true,
    );

    final configs = <String, RulesConfig>{
      'all': all,
      'all, quick': all.copyWith(
        needSixToLeave: false,
        tripleSixForfeit: false,
        endMode: EndMode.firstToWin,
      ),
      'movement only': base.copyWith(blockadeMovement: true),
      'movement + capture': base.copyWith(
        blockadeMovement: true,
        blockadeCapture: true,
      ),
      'unbreakable': base.copyWith(
        blockadeMovement: true,
        blockadeUnbreakable: true,
      ),
      'squatting': base.copyWith(pieceOnBlockade: true),
      'friendly': base.copyWith(blockadeFriendlyRestriction: true),
      'all, banked': all.copyWith(bankedRolls: true),
      'all, teams': all.copyWith(teamsEnabled: true),
      'all, teams, banked': all.copyWith(teamsEnabled: true, bankedRolls: true),
    };

    for (final entry in configs.entries) {
      test('random playouts stay legal: ${entry.key}', () {
        final teams = entry.value.teamsEnabled;
        for (var seed = 1; seed <= 25; seed++) {
          final seats = teams
              ? allSeats
              : [
                  allSeats,
                  [0, 2],
                  [0, 1, 2],
                ][seed % 3];
          final rng = Random(seed);
          final result = playOut(
            seed: seed,
            chooser: rng,
            rules: entry.value,
            activeSeats: seats,
            maxSteps: 60000,
            onState: (state) {
              for (var s = 0; s < 4; s++) {
                expect(state.tokens[s], hasLength(4));
                for (var i = 0; i < 4; i++) {
                  expect(state.rest[s][i], inInclusiveRange(0, 1));
                  if (state.rest[s][i] > 0) {
                    // Only a piece on an opponent blockade ever waits.
                    expect(isOnTrack(state.tokens[s][i]), isTrue,
                        reason: '${state.tokens}');
                  }
                }
              }
            },
          );
          expect(result.finished, isTrue, reason: 'seed $seed ${entry.key}');
          // The same seed and log replay to the same board.
          final replayed = Engine.replay(
            seed: seed,
            log: result.log,
            rules: entry.value,
            activeSeats: seats,
          );
          expect(replayed.tokens, result.state.tokens);
          expect(replayed.rest, result.state.rest);
          expect(replayed.rngState, result.state.rngState);
        }
      });
    }
  });
}
