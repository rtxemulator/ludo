import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

import 'storage_helpers.dart';

/// What a resumed game does from decision [k] on: replay the prefix, then
/// play the remaining logged decisions, recording every die rolled.
({GameState end, List<int> rolls}) resumeFrom(Played game, int k) {
  final prefix = game.save.withLogUnchecked(game.save.log.take(k).toList());
  final replay = SaveReplayer.replay(prefix, verifyCheck: false);
  expect(replay.failure, isNull, reason: 'prefix $k');
  var state = replay.state!;
  expect(state, game.states[k], reason: 'prefix $k');
  final rolls = <int>[];
  for (var i = k; i < game.save.log.length; i++) {
    while (!state.isOver && !state.awaitingMove) {
      final rolled = Engine.roll(state);
      rolls.add(rolled.value);
      state = rolled.state;
    }
    state = Engine.applyEntry(state, game.save.log[i]);
  }
  return (end: state, rolls: rolls);
}

void main() {
  group('resume equivalence', () {
    for (final cell in setupMatrix()) {
      test(cell.name, () {
        for (var g = 0; g < 2; g++) {
          final seed = 31 * g + cell.name.length + 5;
          final game = play(cell.setup, seed, Random(seed * 3));
          final n = game.decisions;
          final prefixes =
              {0, 1, n ~/ 3, n ~/ 2, n - 1, n}.where((k) => k >= 0 && k <= n);
          for (final k in prefixes) {
            final why = '${cell.name} seed $seed prefix $k of $n';
            final resumed = resumeFrom(game, k);
            // The dice after the resume are exactly the dice of the game
            // that was never interrupted, passes and forfeits included.
            expect(
              resumed.rolls,
              [
                for (final r in game.rolls)
                  if (r.decisions >= k) r.value,
              ],
              reason: why,
            );
            expect(resumed.end, game.last, reason: why);
          }
        }
      });
    }
  });

  group('quitting never re-rolls', () {
    for (final cell in setupMatrix()) {
      test(cell.name, () {
        final seed = 17 + cell.name.length;
        final game = play(cell.setup, seed, Random(seed), maxDecisions: 160);
        for (var k = 0; k < game.decisions; k += 3) {
          // Live: the player rolled and was looking at the dice when the app
          // closed (nothing of that roll was saved).
          final live = Engine.nextDecision(game.states[k]);
          // Resumed: replay the saved prefix, roll again.
          final prefix =
              game.save.withLogUnchecked(game.save.log.take(k).toList());
          final resumed =
              Engine.nextDecision(SaveReplayer.replay(prefix).state!);
          expect(resumed, live, reason: '${cell.name} prefix $k');
          expect(resumed.dice, live.dice);
          expect(resumed.bank, live.bank);
          expect(
            Engine.legalMoves(resumed),
            Engine.legalMoves(live),
            reason: '${cell.name} prefix $k',
          );
        }
      });
    }

    test('the state after a replay carries no pending roll', () {
      for (final cell in setupMatrix()) {
        final game = play(cell.setup, 3, Random(3), maxDecisions: 80);
        for (var k = 0; k <= game.decisions; k++) {
          final state = game.states[k];
          if (state.isOver || state.awaitingMove) {
            continue;
          }
          expect(state.dice, isNull, reason: '${cell.name} $k');
        }
      }
    });

    test('replaying twice, or on another device state, gives the same dice',
        () {
      final cell = setupMatrix().firstWhere((c) => c.name == 'classic 4 p');
      final game = play(cell.setup, 4, Random(4), maxDecisions: 100);
      final save = game.save;
      final a = SaveReplayer.replay(save).state!;
      final b = SaveReplayer.replay(save).state!;
      expect(Engine.roll(a).value, Engine.roll(b).value);
      expect(Engine.roll(a).state, Engine.roll(b).state);
    });
  });

  group('banked-roll states', () {
    final banked = setupMatrix().where((c) => c.name.contains('banked'));

    test('resumes in every bank phase, not only at a roll', () {
      var midSpend = 0;
      var leftoverRolling = 0;
      var bankedRolling = 0;
      for (final cell in banked) {
        final game = play(cell.setup, 9, Random(9), maxDecisions: 220);
        for (var k = 0; k <= game.decisions; k++) {
          final state = game.states[k];
          if (state.isOver) {
            continue;
          }
          if (state.awaitingMove) {
            midSpend++;
          } else if (state.bank.isNotEmpty) {
            leftoverRolling++;
          } else {
            bankedRolling++;
          }
          final resumed = resumeFrom(game, k);
          expect(
            resumed.rolls,
            [
              for (final r in game.rolls)
                if (r.decisions >= k) r.value,
            ],
            reason: '${cell.name} prefix $k',
          );
          expect(resumed.end, game.last, reason: '${cell.name} prefix $k');
        }
      }
      // The sweep really visited the interesting states.
      expect(midSpend, greaterThan(0), reason: 'mid-spend states');
      expect(leftoverRolling, greaterThan(0), reason: 'leftover bank, rolling');
      expect(bankedRolling, greaterThan(0), reason: 'rolling an empty bank');
    });

    test('a mid-spend state resumes into the move choice, not a roll', () {
      for (final cell in banked) {
        final game = play(cell.setup, 12, Random(12), maxDecisions: 220);
        for (var k = 1; k <= game.decisions; k++) {
          if (!game.states[k].awaitingMove || game.states[k].isOver) {
            continue;
          }
          final prefix =
              game.save.withLogUnchecked(game.save.log.take(k).toList());
          final state = SaveReplayer.replay(prefix).state!;
          expect(state.awaitingMove, isTrue);
          expect(state.awaitingRoll, isFalse);
          expect(state.bank, game.states[k].bank);
          expect(state.turnSnapshot, game.states[k].turnSnapshot);
          expect(state.currentSeat, game.states[k].currentSeat);
          // Nothing to roll: the choice is on the table and rngState is
          // untouched.
          expect(state.rngState, game.states[k].rngState);
          expect(Engine.nextDecision(state), state);
          return;
        }
      }
      fail('no mid-spend state found');
    });
  });
}
