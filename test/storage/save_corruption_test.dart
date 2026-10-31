import 'dart:convert';
import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

import 'storage_helpers.dart';

void main() {
  final setup = MatchSetup.hotSeat(rules: const RulesConfig.classic());
  final finished = play(MatchSetup.hotSeat(players: 2), 91, Random(3));
  final game = play(setup, 2468, Random(11), maxDecisions: 150);
  final log = game.save.log;

  Map<String, Object?> jsonOf(GameSave save) =>
      jsonDecode(SaveCodec.encode(save)) as Map<String, Object?>;

  group('truncated logs', () {
    test('every cut of the text salvages the whole entries before it', () {
      final text = MoveLogCodec.encode(log);
      for (var cut = 0; cut <= text.length; cut += 7) {
        final json = jsonOf(game.save)..['log'] = text.substring(0, cut);
        final result = SaveCodec.fromJson(json);
        final entries = cut ~/ 2;
        if (cut.isEven) {
          // A cut on an entry boundary is just a shorter log.
          final save = result.save!;
          expect(save.log, log.take(entries).toList(), reason: 'cut $cut');
          final replay = SaveReplayer.replay(save, verifyCheck: false);
          expect(replay.failure, isNull, reason: 'cut $cut');
          expect(replay.state, game.states[entries], reason: 'cut $cut');
          // ... but the fingerprint of the longer log no longer matches.
          final checked = SaveReplayer.replay(save);
          if (entries < log.length) {
            expect(checked.failure?.problem, ReplayProblem.checksumMismatch,
                reason: 'cut $cut');
          }
        } else {
          final failure = result.failure!;
          expect(failure.problem, SaveProblem.corruptLog, reason: 'cut $cut');
          expect(failure.logIndex, entries, reason: 'cut $cut');
          final replay = SaveReplayer.replay(failure.salvage!);
          expect(replay.ok, isTrue, reason: 'cut $cut');
          expect(replay.state, game.states[entries], reason: 'cut $cut');
        }
      }
    });

    test('a half-written save file is not JSON and reports it', () {
      final text = SaveCodec.encode(game.save);
      for (var cut = 0; cut < text.length; cut += 97) {
        final result = SaveCodec.decode(text.substring(0, cut));
        expect(result.save, isNull, reason: 'cut $cut');
        expect(result.failure, isNotNull);
      }
    });
  });

  group('corrupted logs', () {
    test('a bad character stops at that entry and salvages the prefix', () {
      final text = MoveLogCodec.encode(log);
      final at = 37;
      final broken =
          '${text.substring(0, 2 * at)}x${text.substring(2 * at + 1)}';
      final result = SaveCodec.fromJson(jsonOf(game.save)..['log'] = broken);
      expect(result.failure!.problem, SaveProblem.corruptLog);
      expect(result.failure!.logIndex, at);
      final replay = SaveReplayer.replay(result.failure!.salvage!);
      expect(replay.ok, isTrue);
      expect(replay.applied, at);
      expect(replay.state, game.states[at]);
    });

    test('an entry from the wrong seat is rejected where it happens', () {
      for (final at in [0, 1, 40, log.length - 1]) {
        final bad = [...log];
        final e = bad[at];
        bad[at] = MoveLogEntry(
          seat: (e.seat + 1) % 4,
          dice: e.dice,
          tokenIndex: e.tokenIndex,
          unit: e.unit,
        );
        final save = game.save.withLogUnchecked(bad);
        final replay = SaveReplayer.replay(save);
        expect(replay.ok, isFalse, reason: 'at $at');
        final failure = replay.failure!;
        expect(failure.problem, ReplayProblem.entryRejected);
        expect(failure.index, at);
        expect(failure.message, isNotEmpty);
        expect(replay.applied, at);
        expect(replay.total, log.length);
        expect(replay.state, game.states[at], reason: 'at $at');
        expect(replay.resumable, isFalse);
      }
    });

    test('a wrong die is rejected, the state stays at the last valid one', () {
      final at = 25;
      final bad = [...log];
      final e = bad[at];
      bad[at] = MoveLogEntry(
        seat: e.seat,
        dice: e.dice == 1 ? 2 : e.dice - 1,
        tokenIndex: e.tokenIndex,
        unit: e.unit,
      );
      final replay = SaveReplayer.replay(game.save.withLogUnchecked(bad));
      expect(replay.failure?.problem, ReplayProblem.entryRejected);
      expect(replay.failure?.index, at);
      expect(replay.state, game.states[at]);
    });

    test('a token that cannot move is rejected where it happens', () {
      // Replace every token index in turn until the engine refuses one.
      var refused = 0;
      for (var at = 0; at < 60; at++) {
        final e = log[at];
        final bad = [...log];
        bad[at] = MoveLogEntry(
          seat: e.seat,
          dice: e.dice,
          tokenIndex: (e.tokenIndex + 1) % 4,
          unit: e.unit,
        );
        final replay = SaveReplayer.replay(game.save.withLogUnchecked(bad));
        // A legal swap changes the game and is only caught further on.
        expect(replay.failure?.problem, ReplayProblem.entryRejected);
        expect(replay.failure!.index, greaterThanOrEqualTo(at));
        if (replay.failure!.index == at) {
          refused++;
          expect(replay.state, game.states[at]);
        }
      }
      expect(refused, greaterThan(10));
    });

    test('entries after the game ended are rejected', () {
      expect(finished.last.isOver, isTrue);
      const extra = MoveLogEntry(seat: 0, dice: 3, tokenIndex: 0);
      final save =
          finished.save.withLogUnchecked([...finished.save.log, extra]);
      final replay = SaveReplayer.replay(save);
      expect(replay.failure?.problem, ReplayProblem.entryRejected);
      expect(replay.failure?.index, finished.save.log.length);
      expect(replay.state, finished.last);
      expect(replay.failure?.message, contains('over'));
    });

    test('a wrong seed does not replay', () {
      final other = GameSave(
        id: game.save.id,
        name: 'x',
        createdAt: t0,
        updatedAt: t0,
        setup: setup,
        seed: game.seed + 1,
        log: log,
      );
      expect(SaveReplayer.replay(other).ok, isFalse);
      expect(SaveReplayer.replay(other).failure?.problem,
          ReplayProblem.entryRejected);
    });

    test('a different rule set does not replay silently', () {
      final other = GameSave(
        id: game.save.id,
        name: 'x',
        createdAt: t0,
        updatedAt: t0,
        setup: setup.withRules(const RulesConfig.quick()),
        seed: game.seed,
        log: log,
        check: game.save.check,
      );
      expect(SaveReplayer.replay(other).ok, isFalse);
    });
  });

  group('fingerprint check', () {
    test('a flipped check is an incompatible save, not a rejected entry', () {
      final flipped = game.save.check!
          .replaceRange(0, 1, game.save.check![0] == '0' ? '1' : '0');
      final save = GameSave(
        id: 'c',
        name: 'c',
        createdAt: t0,
        updatedAt: t0,
        setup: setup,
        seed: game.seed,
        log: log,
        check: flipped,
      );
      final replay = SaveReplayer.replay(save);
      expect(replay.failure?.problem, ReplayProblem.checksumMismatch);
      expect(replay.failure?.incompatible, isTrue);
      expect(replay.failure?.index, log.length);
      // Every entry applied, so the state is the full replay.
      expect(replay.state, game.last);
      expect(replay.applied, log.length);
      // Unverified, it replays fine; the timeline never checks.
      expect(SaveReplayer.replay(save, verifyCheck: false).ok, isTrue);
      expect(SaveReplayer.timeline(save).failure, isNull);
    });

    test('no check means nothing to compare', () {
      final save = game.save.withLogUnchecked(log);
      expect(save.check, isNull);
      expect(SaveReplayer.replay(save).ok, isTrue);
    });
  });

  group('timeline and setup failures', () {
    test('a timeline stops at the last valid entry and reports it', () {
      final bad = [...log];
      final e = bad[30];
      bad[30] = MoveLogEntry(
        seat: (e.seat + 2) % 4,
        dice: e.dice,
        tokenIndex: e.tokenIndex,
      );
      final timeline = SaveReplayer.timeline(game.save.withLogUnchecked(bad));
      expect(timeline.failure?.index, 30);
      expect(timeline.applied, 30);
      expect(timeline.states.length, 31);
      expect(timeline.states, game.states.take(31).toList());
    });

    test('an empty log has just the start state', () {
      final empty = GameSave.begin(id: 'e', now: t0, setup: setup, seed: 5);
      final timeline = SaveReplayer.timeline(empty);
      expect(timeline.states, [setup.newGame(5)]);
      expect(timeline.applied, 0);
      expect(timeline.failure, isNull);
      final replay = SaveReplayer.replay(empty);
      expect(replay.ok, isTrue);
      expect(replay.applied, 0);
      expect(replay.resumable, isTrue);
    });

    test('a setup that cannot start a match is reported, not thrown', () {
      final lonely = MatchSetup(
        seats: const [SeatConfig(), null, null, null],
      );
      final save = GameSave(
        id: 'l',
        name: 'l',
        createdAt: t0,
        updatedAt: t0,
        setup: lonely,
        seed: 1,
      );
      final replay = SaveReplayer.replay(save);
      expect(replay.failure?.problem, ReplayProblem.invalidSetup);
      expect(replay.state, isNull);
      expect(replay.resumable, isFalse);
      final timeline = SaveReplayer.timeline(save);
      expect(timeline.failure?.problem, ReplayProblem.invalidSetup);
      expect(timeline.states, isEmpty);
      expect(timeline.applied, 0);
    });
  });
}
