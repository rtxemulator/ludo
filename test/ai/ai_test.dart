import 'dart:math';

import 'package:ludo/ai/ai.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:test/test.dart';

import '../../tool/tournament.dart';
import '../engine/helpers.dart';

/// Awaiting-move states from random games under [rules].
List<GameState> _positions(RulesConfig rules, {int games = 6, int every = 5}) {
  final out = <GameState>[];
  for (var seed = 1; seed <= games; seed++) {
    final chooser = Random(seed);
    var state = Engine.newGame(seed: seed, rules: rules);
    var n = 0;
    while (!state.isOver && n < 3000) {
      if (!state.awaitingMove) {
        state = Engine.roll(state).state;
        continue;
      }
      final moves = Engine.legalMoves(state);
      if (n++ % every == 0) {
        out.add(state);
      }
      state = Engine.apply(state, moves[chooser.nextInt(moves.length)]);
    }
  }
  return out;
}

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

void main() {
  group('AiWeights', () {
    test('vector round trip', () {
      const w = AiWeights();
      final back = AiWeights.fromVector(w.toVector());
      expect(back.toVector(), w.toVector());
      expect(w.toVector().length, AiWeights.names.length);
    });
  });

  group('evaluation', () {
    const w = AiWeights();

    test('is zero-sum with two units', () {
      for (final s in _positions(const RulesConfig(), games: 3, every: 3)) {
        if (s.activeSeats.length != 4) {
          continue;
        }
      }
      final duel = Engine.newGame(seed: 3, activeSeats: [0, 2]);
      var state = duel;
      final chooser = Random(1);
      for (var i = 0; i < 200 && !state.isOver; i++) {
        if (!state.awaitingMove) {
          state = Engine.roll(state).state;
          continue;
        }
        final moves = Engine.legalMoves(state);
        state = Engine.apply(state, moves[chooser.nextInt(moves.length)]);
        if (!state.isOver) {
          expect(
            evaluate(state, 0, w) + evaluate(state, 2, w),
            closeTo(0, 1e-9),
          );
        }
      }
    });

    test('progress counts, the yard is zero', () {
      final yard = makeState(activeSeats: [0, 2]);
      final ahead = makeState(activeSeats: [
        0,
        2
      ], tokens: {
        0: [20, -1, -1, -1],
      });
      expect(evaluate(yard, 0, w), 0);
      expect(evaluate(ahead, 0, w), greaterThan(20));
    });

    test('a token inside an enemy\'s range is worth less', () {
      // Seat 2 token at abs 20 (rel 20 -> abs (20 + 26) % 52 = 46; use abs
      // directly through relative positions).
      final enemyAbs = 30;
      final enemyRel = relativeFor(2, enemyAbs);
      final exposed = makeState(activeSeats: [
        0,
        2
      ], tokens: {
        0: [33, -1, -1, -1], // 3 ahead of the enemy
        2: [enemyRel, -1, -1, -1],
      });
      final distant = makeState(activeSeats: [
        0,
        2
      ], tokens: {
        0: [40, -1, -1, -1], // 10 ahead: out of range
        2: [enemyRel, -1, -1, -1],
      });
      final gap = evaluate(distant, 0, w) - evaluate(exposed, 0, w);
      // 7 squares of progress plus the exposure penalty and the threat swing.
      expect(gap, greaterThan(7));
    });

    test('safe squares and the home column are immune', () {
      final enemyRel = relativeFor(2, 30);
      // abs 34 is a star square, abs 33 is not.
      final onStar = makeState(activeSeats: [
        0,
        2
      ], tokens: {
        0: [34, -1, -1, -1],
        2: [enemyRel, -1, -1, -1],
      });
      final onPlain = makeState(activeSeats: [
        0,
        2
      ], tokens: {
        0: [33, -1, -1, -1],
        2: [enemyRel, -1, -1, -1],
      });
      expect(evaluate(onStar, 0, w), greaterThan(evaluate(onPlain, 0, w)));
    });

    test('a finished match is worth the placement', () {
      final won = makeState(
        activeSeats: [0, 2],
        rules: const RulesConfig(endMode: EndMode.firstToWin),
        tokens: {
          0: [56, 56, 56, 56],
        },
        finishOrder: [0],
      );
      expect(won.isOver, isTrue);
      expect(evaluate(won, 0, w), AiWeights.placement.first);
      expect(evaluate(won, 2, w), -AiWeights.placement.first);
    });
  });

  group('search', () {
    test('picks the capture', () {
      final victimRel = relativeFor(1, 24);
      final state = makeState(
        activeSeats: [0, 1],
        dice: 4,
        tokens: {
          0: [20, 30, -1, -1],
          1: [victimRel, -1, -1, -1],
        },
      );
      final legal = Engine.legalMoves(state);
      for (final level in [AiLevel.medium, AiLevel.hard, AiLevel.expert]) {
        final move = AiPlayer.nodes(level, 3000).choose(state, legal);
        expect(move.tokenIndex, 0, reason: level.name);
      }
    });

    test('takes the finish when it can', () {
      final state = makeState(
        activeSeats: [0, 2],
        dice: 4,
        tokens: {
          0: [52, 20, -1, -1],
          2: [relativeFor(2, 5), -1, -1, -1],
        },
      );
      final move = AiPlayer.nodes(AiLevel.hard, 3000)
          .choose(state, Engine.legalMoves(state));
      expect(move.tokenIndex, 0);
    });

    test('equal yard tokens collapse to the lowest index', () {
      final state = makeState(
        activeSeats: [0, 2],
        dice: 6,
        tokens: {
          0: [-1, -1, -1, -1],
        },
      );
      final legal = Engine.legalMoves(state);
      expect(legal.length, 4);
      final player = AiPlayer.nodes(AiLevel.expert, 3000);
      expect(player.choose(state, legal).tokenIndex, 0);
      expect(player.lastNodes, 0, reason: 'a forced move costs no search');
    });

    test('is deterministic', () {
      for (final s in _positions(const RulesConfig(), games: 3, every: 7)) {
        final legal = Engine.legalMoves(s);
        final a = AiPlayer.nodes(AiLevel.hard, 400).choose(s, legal);
        final b = AiPlayer.nodes(AiLevel.hard, 400).choose(s, legal);
        expect(a, b);
      }
    });

    test('deeper tiers complete deeper searches', () {
      final s = makeState(
        activeSeats: [0, 2],
        dice: 3,
        tokens: {
          0: [10, 20, -1, -1],
          2: [relativeFor(2, 30), -1, -1, -1],
        },
      );
      final legal = Engine.legalMoves(s);
      final medium = AiPlayer.nodes(AiLevel.medium, 100000)..choose(s, legal);
      final hard = AiPlayer.nodes(AiLevel.hard, 100000)..choose(s, legal);
      expect(medium.lastDepth, 1);
      expect(hard.lastDepth, 2);
      expect(hard.lastNodes, greaterThan(medium.lastNodes));
    });

    test('a node budget keeps the work bounded', () {
      final s = makeState(
        activeSeats: [0, 2],
        dice: 3,
        tokens: {
          0: [10, 20, -1, -1],
          2: [relativeFor(2, 30), -1, -1, -1],
        },
      );
      final player = AiPlayer.nodes(AiLevel.expert, 150)
        ..choose(s, Engine.legalMoves(s));
      expect(player.lastNodes, lessThanOrEqualTo(151));
    });

    test('the clock budget is respected', () {
      final s = _positions(const RulesConfig(bankedRolls: true), games: 2)
          .firstWhere((s) => Engine.legalMoves(s).length > 1);
      final player = AiPlayer(AiLevel.expert);
      final sw = Stopwatch()..start();
      player.choose(s, Engine.legalMoves(s));
      expect(sw.elapsedMilliseconds, lessThan(600));
    });
  });

  group('position key', () {
    test('ignores token order, generator state and turn counter', () {
      final a = makeState(tokens: {
        0: [3, 9, -1, 20],
      }, rngState: 5);
      final b = makeState(tokens: {
        0: [20, -1, 9, 3],
      }, rngState: 99, turnNumber: 7);
      expect(positionKey(a, 0, 0), positionKey(b, 0, 0));
    });

    test('tells apart seat, die and progress counters', () {
      final a = makeState(tokens: {
        0: [3, -1, -1, -1],
      });
      expect(positionKey(a, 0, 0), isNot(positionKey(a, 1, 0)));
      expect(positionKey(a, 0, 0), isNot(positionKey(a, 0, 1)));
      expect(
          positionKey(a, 0, 0), isNot(positionKey(a.copyWith(dice: 2), 0, 0)));
      expect(positionKey(a, 0, 0),
          isNot(positionKey(a.copyWith(currentSeat: 1), 0, 0)));
    });

    test('banked: spending order does not matter', () {
      final start = makeMoving(bank: [
        3,
        4
      ], tokens: {
        0: [10, 20, -1, -1],
      });
      GameState spend(GameState s, int token, int die) {
        final move = Engine.legalMoves(s).firstWhere(
            (m) => m.tokenIndex == token && s.bank[m.dieIndex] == die);
        return Engine.apply(s, move);
      }

      final x = spend(spend(start, 0, 3), 1, 4);
      final y = spend(spend(start, 1, 4), 0, 3);
      expect(positionKey(x, 0, 0), positionKey(y, 0, 0));
    });
  });

  group('fairness', () {
    for (final entry in _configs.entries) {
      test('choice ignores the generator state: ${entry.key}', () {
        for (final s in _positions(entry.value, games: 2, every: 12)) {
          final legal = Engine.legalMoves(s);
          for (final level in [AiLevel.medium, AiLevel.hard, AiLevel.expert]) {
            final a = AiPlayer.nodes(level, 120).choose(s, legal);
            final b = AiPlayer.nodes(level, 120)
                .choose(s.copyWith(rngState: 0x5EEDFACE), legal);
            expect(a, b, reason: '${level.name} on $s');
          }
        }
      });
    }
  });

  group('rule coverage', () {
    for (final entry in _configs.entries) {
      test('AI playouts finish with legal moves only: ${entry.key}', () {
        final levels = [AiLevel.medium, AiLevel.hard, AiLevel.expert];
        for (var seed = 1; seed <= 2; seed++) {
          var state = Engine.newGame(seed: seed, rules: entry.value);
          final players = [
            for (final level in levels) AiPlayer.nodes(level, 120),
            AiPlayer.nodes(AiLevel.easy, 1),
          ];
          var decisions = 0;
          while (!state.isOver && decisions < 4000) {
            if (!state.awaitingMove) {
              state = Engine.roll(state).state;
              continue;
            }
            final legal = Engine.legalMoves(state);
            final move = players[state.currentSeat].choose(state, legal);
            expect(legal, contains(move));
            state = Engine.apply(state, move);
            decisions++;
          }
          expect(state.isOver, isTrue, reason: '${entry.key} seed $seed');
        }
      });
    }

    test('random rule sets and seat layouts', () {
      final rng = Random(11);
      for (var i = 0; i < 12; i++) {
        final teams = rng.nextBool();
        final rules = RulesConfig(
          endMode: EndMode.values[rng.nextInt(2)],
          needSixToLeave: rng.nextBool(),
          extraTurnOnSix: rng.nextBool(),
          tripleSixForfeit: rng.nextBool(),
          extraTurnOnCapture: rng.nextBool(),
          extraTurnOnHome: rng.nextBool(),
          exactRollToFinish: rng.nextBool(),
          blockades: rng.nextBool(),
          teamsEnabled: teams,
          bankedRolls: rng.nextBool(),
          blockadeMovement: rng.nextBool(),
          blockadeCapture: rng.nextBool(),
          blockadeUnbreakable: rng.nextBool(),
          blockadeFriendlyRestriction: rng.nextBool(),
          pieceOnBlockade: rng.nextBool(),
        );
        final shuffled = [0, 1, 2, 3]..shuffle(rng);
        final seats =
            teams ? [0, 1, 2, 3] : shuffled.sublist(0, 2 + rng.nextInt(3));
        var state = Engine.newGame(seed: i, rules: rules, activeSeats: seats);
        final level = AiLevel.values[1 + rng.nextInt(3)];
        final player = AiPlayer.nodes(level, 100);
        var decisions = 0;
        while (!state.isOver && decisions < 4000) {
          if (!state.awaitingMove) {
            state = Engine.roll(state).state;
            continue;
          }
          final legal = Engine.legalMoves(state);
          final move = player.choose(state, legal);
          expect(legal, contains(move), reason: '$rules');
          state = Engine.apply(state, move);
          decisions++;
        }
        expect(state.isOver, isTrue, reason: '$rules seats $seats');
      }
    });
  });

  group('tournament harness', () {
    test('plays reproducible, finished games', () async {
      final a = PlayerSpec.parse('medium:150');
      const b = PlayerSpec('random');
      final one = await runMatch(
        a: a,
        b: b,
        layout: Layout.duel,
        rules: rulesByName('classic'),
        games: 8,
      );
      final two = await runMatch(
        a: a,
        b: b,
        layout: Layout.duel,
        rules: rulesByName('classic'),
        games: 8,
      );
      expect(one.unfinished, 0);
      expect(one.wins, two.wins);
      expect(one.games, 8);
    });

    test('every layout runs', () async {
      for (final layout in Layout.values) {
        final t = await runMatch(
          a: PlayerSpec.parse('medium:100'),
          b: const PlayerSpec('easy'),
          layout: layout,
          rules: rulesByName('strategic'),
          games: 4,
        );
        expect(t.unfinished, 0, reason: layout.name);
      }
    });
  });
}
