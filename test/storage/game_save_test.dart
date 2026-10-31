import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

import 'storage_helpers.dart';

void main() {
  final setup = MatchSetup.hotSeat(players: 2);

  group('names', () {
    test('auto-name is the date and time, zero padded', () {
      expect(
          GameSave.autoName(DateTime(2026, 10, 26, 14, 5)), '2026-10-26 14:05');
      expect(GameSave.autoName(DateTime(2026, 1, 2, 3, 4)), '2026-01-02 03:04');
    });

    test('cleanName trims, flattens line breaks and cuts', () {
      expect(GameSave.cleanName('  Friday game  '), 'Friday game');
      expect(GameSave.cleanName('a\nb\r\nc\td'), 'a b c d');
      expect(GameSave.cleanName(''), isNull);
      expect(GameSave.cleanName(' \n\t '), isNull);
      expect(GameSave.cleanName(null), isNull);
      final long = GameSave.cleanName('x' * 100)!;
      expect(long.length, maxSaveNameLength);
    });

    test('cutting does not split an emoji', () {
      final cut = GameSave.cleanName('😀' * 50)!;
      expect(cut.runes.length, maxSaveNameLength);
    });

    test('a blank name becomes the auto-name of createdAt', () {
      final save = GameSave.begin(id: 'a', now: t0, setup: setup, seed: 1);
      expect(save.name, GameSave.autoName(t0));
      expect(save.withName('   ').name, GameSave.autoName(t0));
      expect(save.withName(' Mine ').name, 'Mine');
    });
  });

  group('ids', () {
    test('newId is unique and carries the time', () {
      final rng = Random(5);
      final ids = {for (var i = 0; i < 500; i++) GameSave.newId(t0, rng)};
      expect(ids.length, 500);
      expect(
        GameSave.newId(t0, Random(1))
            .startsWith(t0.millisecondsSinceEpoch.toRadixString(36)),
        isTrue,
      );
    });
  });

  group('GameSave', () {
    test('begin makes an empty, checked save of the start position', () {
      final save = GameSave.begin(id: 'a', now: t0, setup: setup, seed: 77);
      expect(save.log, isEmpty);
      expect(save.moves, 0);
      expect(save.finished, isFalse);
      expect(save.schemaVersion, saveSchemaVersion);
      expect(save.createdAt, t0);
      expect(save.updatedAt, t0);
      expect(save.summary, const SaveSummary());
      expect(save.check, StateFingerprint.of(setup.newGame(77)));
      expect(SaveReplayer.replay(save).ok, isTrue);
    });

    test('times are normalised to UTC milliseconds', () {
      final local = DateTime(2026, 10, 26, 14, 5, 7, 123, 456);
      final save = GameSave(
        id: 'a',
        name: 'n',
        createdAt: local,
        updatedAt: local,
        setup: setup,
        seed: 1,
      );
      expect(save.createdAt.isUtc, isTrue);
      expect(save.createdAt.microsecond, 0);
      expect(
          save.createdAt.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
    });

    test('the log is unmodifiable and withEntry copies', () {
      final first = GameSave.begin(id: 'a', now: t0, setup: setup, seed: 3);
      final game = play(setup, 3, Random(1), maxDecisions: 3);
      expect(
          () => game.save.log.add(game.save.log.first), throwsUnsupportedError);
      expect(first.log, isEmpty);
      expect(game.save.log.length, 3);
    });

    test('withEntry tracks updatedAt, summary, check and finished', () {
      final game = play(setup, 11, Random(2));
      expect(game.last.isOver, isTrue);
      final save = game.save;
      expect(save.finished, isTrue);
      expect(save.updatedAt.isAfter(save.createdAt), isTrue);
      expect(save.summary.turnNumber, game.last.turnNumber);
      expect(save.summary.finishOrder, game.last.finishOrder);
      expect(save.check, StateFingerprint.of(game.last));
    });

    test('finishOrder is only kept once the game is over', () {
      final game = play(MatchSetup.hotSeat(), 21, Random(3), maxDecisions: 40);
      expect(game.last.isOver, isFalse);
      expect(game.save.summary.finishOrder, isEmpty);
      expect(game.save.finished, isFalse);
    });

    test('withName keeps everything else, updatedAt included', () {
      final game = play(setup, 12, Random(4), maxDecisions: 10);
      final renamed = game.save.withName('Renamed');
      expect(renamed.name, 'Renamed');
      expect(renamed.updatedAt, game.save.updatedAt);
      expect(renamed.log, game.save.log);
      expect(renamed.check, game.save.check);
      expect(renamed == game.save, isFalse);
      expect(renamed.withName(game.save.name), game.save);
      expect(renamed.withName(game.save.name).hashCode, game.save.hashCode);
    });

    test('a state from after a roll fails the replay check', () {
      // The footgun documented for the controller: autosave must pass the
      // state Engine.apply returned, not one after a later roll.
      final game = play(setup, 13, Random(5), maxDecisions: 6);
      final before = game.last;
      final moves = Engine.legalMoves(Engine.nextDecision(before));
      final rolled = Engine.nextDecision(before);
      final entry = Engine.logEntry(rolled, moves.first);
      final after = Engine.apply(rolled, moves.first);
      final wrongState = Engine.nextDecision(after);
      final good = game.save.withEntry(entry, after, t0);
      final bad = game.save.withEntry(entry, wrongState, t0);
      expect(SaveReplayer.replay(good).ok, isTrue);
      final failure = SaveReplayer.replay(bad).failure;
      expect(failure?.problem, ReplayProblem.checksumMismatch);
    });
  });

  group('StateFingerprint', () {
    test('16 lowercase hex digits, stable and sensitive', () {
      final a = setup.newGame(1);
      final b = setup.newGame(2);
      final fa = StateFingerprint.of(a);
      expect(fa, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(StateFingerprint.of(setup.newGame(1)), fa);
      expect(StateFingerprint.of(b), isNot(fa));
      final rolled = Engine.nextDecision(a);
      expect(StateFingerprint.of(rolled), isNot(fa));
    });

    test('differs along a whole game', () {
      final game = play(setup, 31, Random(8), maxDecisions: 200);
      final prints = game.states.map(StateFingerprint.of).toSet();
      expect(prints.length, game.states.length);
    });
  });
}
