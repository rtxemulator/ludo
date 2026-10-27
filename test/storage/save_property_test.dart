import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

import 'storage_helpers.dart';

void main() {
  const gamesPerSetup = 6;

  group('property: autosave, encode, decode, replay', () {
    for (final cell in setupMatrix()) {
      test(cell.name, () {
        for (var g = 0; g < gamesPerSetup; g++) {
          final seed = 1000 * g + cell.name.length * 7 + 13;
          final game = play(cell.setup, seed, Random(seed ^ 0x5bd1e995));
          final why = '${cell.name} seed $seed';

          // Through the JSON text and back.
          final text = SaveCodec.encode(game.save);
          final decoded = SaveCodec.decode(text);
          expect(decoded.failure, isNull, reason: why);
          final save = decoded.save!;
          expect(save, game.save, reason: why);

          // Replay equals the live game, equals Engine.replay.
          final replay = SaveReplayer.replay(save);
          expect(replay.failure, isNull, reason: why);
          expect(replay.applied, game.decisions, reason: why);
          expect(replay.state, game.last, reason: why);
          expect(
            Engine.replay(
              seed: seed,
              log: save.log,
              rules: cell.setup.rules,
              activeSeats: cell.setup.activeSeats,
            ),
            game.last,
            reason: why,
          );
          expect(replay.resumable, !game.last.isOver, reason: why);

          // The summary and the finished flag match the replayed state.
          expect(save.finished, replay.state!.isOver, reason: why);
          expect(save.summary, SaveSummary.of(replay.state!), reason: why);

          // Every intermediate state of the timeline is the live one.
          final timeline = SaveReplayer.timeline(save);
          expect(timeline.failure, isNull, reason: why);
          expect(timeline.states, game.states, reason: why);
        }
      });
    }
  });

  group('property: every autosave along the way is valid', () {
    for (final cell in setupMatrix().where((c) =>
        c.name.contains('banked') ||
        c.name.startsWith('blockade') ||
        c.name == 'classic 4 p')) {
      test(cell.name, () {
        final seed = 777 + cell.name.length;
        final game = play(cell.setup, seed, Random(seed));
        var save = GameSave.begin(
          id: 'inc',
          now: t0,
          setup: cell.setup,
          seed: seed,
        );
        var live = cell.setup.newGame(seed);
        // Rebuild the autosaves one decision at a time from the log, as the
        // controller's writes would arrive, and check a sample of them.
        for (var k = 0; k < game.save.log.length; k++) {
          final entry = game.save.log[k];
          live = Engine.applyEntry(live, entry);
          save = save.withEntry(entry, live, t0.add(Duration(seconds: k)));
          if (k % 11 == 0 || k == game.save.log.length - 1) {
            final back = SaveCodec.decode(SaveCodec.encode(save)).save!;
            final replay = SaveReplayer.replay(back);
            expect(replay.failure, isNull, reason: 'decision $k');
            expect(replay.state, game.states[k + 1], reason: 'decision $k');
          }
        }
        expect(save.log, game.save.log);
      });
    }
  });
}
