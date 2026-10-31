import 'dart:convert';
import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

import 'storage_helpers.dart';

void main() {
  group('property: every step rebuilds the decision', () {
    for (final cell in setupMatrix()) {
      test(cell.name, () {
        for (var g = 0; g < 4; g++) {
          final seed = 77 * g + cell.name.length * 5 + 3;
          final game = play(cell.setup, seed, Random(seed ^ 0x2545f491));
          final why = '${cell.name} seed $seed';
          final script = ReplayScript.of(game.save);

          expect(script.failure, isNull, reason: why);
          expect(script.partial, isFalse, reason: why);
          expect(script.length, game.decisions, reason: why);
          expect(script.states, game.states, reason: why);
          expect(script.endsInGameOver, game.last.isOver, reason: why);

          for (var k = 1; k <= script.length; k++) {
            final step = script.step(k);
            final r = '$why step $k';
            expect(step.index, k, reason: r);
            expect(step.entry, game.save.log[k - 1], reason: r);
            expect(step.before, game.states[k - 1], reason: r);
            expect(step.after, game.states[k], reason: r);
            expect(step.ready.awaitingMove, isTrue, reason: r);
            expect(step.ready.currentSeat, step.entry.seat, reason: r);
            expect(step.roller, step.entry.seat, reason: r);
            expect(Engine.apply(step.ready, step.move), step.after, reason: r);
            expect(Engine.legalMoves(step.ready), contains(step.move),
                reason: r);
            if (!cell.setup.rules.bankedRolls) {
              expect(step.ready.dice, step.entry.dice, reason: r);
              expect(step.revertedBefore, isFalse, reason: r);
            }
          }
        }
      });
    }
  });

  test('a damaged log gives a shorter script and says where it stopped', () {
    final game = play(MatchSetup.hotSeat(players: 2), 91, Random(3));
    final log = game.save.log;
    final cut = log.take(12).toList();
    final bad = [
      ...cut,
      // A move for the wrong seat can never apply.
      MoveLogEntry(
        seat: (log[12].seat + 1) % 4,
        dice: log[12].dice,
        tokenIndex: log[12].tokenIndex,
      ),
      ...log.skip(13),
    ];
    final save = GameSave(
      id: game.save.id,
      name: game.save.name,
      createdAt: game.save.createdAt,
      updatedAt: game.save.updatedAt,
      setup: game.save.setup,
      seed: game.save.seed,
      log: bad,
      finished: false,
      summary: const SaveSummary(),
    );
    final script = ReplayScript.of(save);
    expect(script.partial, isTrue);
    expect(script.length, 12);
    expect(script.logLength, bad.length);
    expect(script.failure!.problem, ReplayProblem.entryRejected);
    expect(script.states, game.states.take(13).toList());
  });

  test('an empty log has nothing to play', () {
    final save = GameSave.begin(
      id: 'e',
      now: t0,
      setup: MatchSetup.hotSeat(players: 2),
      seed: 5,
    );
    final script = ReplayScript.of(save);
    expect(script.hasMoves, isFalse);
    expect(script.length, 0);
    expect(script.states, hasLength(1));
  });

  group('SaveLibrary.openReplay', () {
    late InMemorySaveStore store;
    late SaveLibrary library;
    setUp(() {
      store = InMemorySaveStore();
      library = SaveLibrary(store);
    });

    Future<SaveListItem> item(String id) async =>
        (await store.list()).firstWhere((i) => i.id == id);

    test('opens finished and in-progress saves whole', () async {
      final done = play(MatchSetup.hotSeat(players: 2), 91, Random(3)).save;
      final live = play(
        MatchSetup.hotSeat(players: 2),
        12,
        Random(4),
        maxDecisions: 9,
      ).save;
      await store.put(_renamed(done, 'done'));
      await store.put(_renamed(live, 'live'));

      final d = await library.openReplay(await item('done'));
      expect(d.ok, isTrue);
      expect(d.partial, isFalse);
      expect(d.script!.endsInGameOver, isTrue);
      expect(d.playable, done.log.length);

      final l = await library.openReplay(await item('live'));
      expect(l.ok, isTrue);
      expect(l.script!.endsInGameOver, isFalse);
      expect(l.playable, 9);
    });

    test('waits for a write that is still queued', () async {
      final live = play(
        MatchSetup.hotSeat(players: 2),
        12,
        Random(4),
        maxDecisions: 9,
      ).save;
      await store.put(_renamed(live, 'g'));
      final first = await item('g');
      final longer = play(
        MatchSetup.hotSeat(players: 2),
        12,
        Random(4),
        maxDecisions: 14,
      ).save;
      library.queue.put(_renamed(longer, 'g'));
      final opened = await library.openReplay(first);
      expect(opened.playable, 14);
    });

    test('a damaged log replays up to its last valid entry', () async {
      final game = play(
        MatchSetup.hotSeat(players: 2),
        12,
        Random(4),
        maxDecisions: 20,
      );
      final json = jsonDecode(SaveCodec.encode(_renamed(game.save, 'x')))
          as Map<String, Object?>;
      final text = json['log']! as String;
      json['log'] = '${text.substring(0, 14)}zz${text.substring(16)}';
      store.putRaw('x', jsonEncode(json));
      final row = await item('x');
      expect(row.openable, isFalse);
      final opened = await library.openReplay(row);
      expect(opened.ok, isTrue);
      expect(opened.salvaged, isTrue);
      expect(opened.partial, isTrue);
      expect(opened.playable, 7);
    });

    test('a save that is too new, or garbage, is refused', () async {
      store.putRaw('junk', 'not json');
      final opened = await library.openReplay(await item('junk'));
      expect(opened.ok, isFalse);
      expect(opened.problem, isNotNull);

      final game = play(
        MatchSetup.hotSeat(players: 2),
        12,
        Random(4),
        maxDecisions: 5,
      );
      final json = jsonDecode(SaveCodec.encode(_renamed(game.save, 'new')))
          as Map<String, Object?>;
      json['schemaVersion'] = 999;
      store.putRaw('new', jsonEncode(json));
      expect((await library.openReplay(await item('new'))).ok, isFalse);
    });

    test('a replay that no longer matches the engine is refused', () async {
      final game = play(
        MatchSetup.hotSeat(players: 2),
        12,
        Random(4),
        maxDecisions: 8,
      );
      final json = jsonDecode(SaveCodec.encode(_renamed(game.save, 'drift')))
          as Map<String, Object?>;
      json['check'] = '0000000000000000';
      store.putRaw('drift', jsonEncode(json));
      final row = await item('drift');
      final opened = await library.openReplay(row);
      expect(opened.ok, isFalse);
    });

    test('a missing id is refused', () async {
      final opened = await library.openReplay(
        SaveListItem(
          id: 'nope',
          name: 'n',
          createdAt: t0,
          updatedAt: t0,
          status: SaveStatus.ok,
        ),
      );
      expect(opened.ok, isFalse);
    });
  });
}

GameSave _renamed(GameSave s, String id) => GameSave(
      id: id,
      name: id,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      setup: s.setup,
      seed: s.seed,
      log: s.log,
      finished: s.finished,
      summary: s.summary,
      check: s.check,
    );
