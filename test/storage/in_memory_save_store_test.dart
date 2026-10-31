import 'dart:convert';
import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

import 'storage_helpers.dart';

GameSave _save(String id, int minute, {int moves = 5, int players = 2}) {
  final game = play(
    MatchSetup.hotSeat(players: players),
    id.hashCode & 0xffff,
    Random(minute),
    maxDecisions: moves,
  );
  final base = game.save;
  return GameSave(
    id: id,
    name: 'game $id',
    createdAt: t0,
    updatedAt: t0.add(Duration(minutes: minute)),
    setup: base.setup,
    seed: base.seed,
    log: base.log,
    summary: base.summary,
    check: base.check,
  );
}

void main() {
  late InMemorySaveStore store;
  setUp(() => store = InMemorySaveStore());

  group('put / get', () {
    test('an empty store lists nothing and knows no id', () async {
      expect(await store.list(), isEmpty);
      expect(await store.get('nope'), isNull);
      expect(store.length, 0);
    });

    test('put then get returns an equal save', () async {
      final save = _save('a', 1);
      await store.put(save);
      final back = await store.get('a');
      expect(back, isA<SaveDecoded>());
      expect(back!.save, save);
      expect(store.length, 1);
    });

    test('put replaces the save with the same id (autosave)', () async {
      final game = play(MatchSetup.hotSeat(), 5, Random(1), maxDecisions: 30);
      var save = GameSave.begin(
        id: 'one',
        now: t0,
        setup: game.setup,
        seed: game.seed,
      );
      var live = game.setup.newGame(game.seed);
      for (var k = 0; k < 30; k++) {
        live = Engine.applyEntry(live, game.save.log[k]);
        save = save.withEntry(
            game.save.log[k], live, t0.add(Duration(seconds: k + 1)));
        await store.put(save);
      }
      expect(store.length, 1);
      final back = (await store.get('one'))!.save!;
      expect(back.moves, 30);
      expect(back, save);
      expect(SaveReplayer.replay(back).state, game.last);
    });

    test('the store keeps its own copy of the data', () async {
      final save = _save('a', 1);
      await store.put(save);
      final first = (await store.get('a'))!.save!;
      final second = (await store.get('a'))!.save!;
      expect(identical(first, second), isFalse);
      expect(first, second);
    });
  });

  group('list', () {
    test('newest updatedAt first, ties by id', () async {
      await store.put(_save('old', 1));
      await store.put(_save('new', 9));
      await store.put(_save('mid', 5));
      await store.put(_save('b-tie', 5));
      await store.put(_save('a-tie', 5));
      final ids = (await store.list()).map((i) => i.id).toList();
      expect(ids, ['new', 'a-tie', 'b-tie', 'mid', 'old']);
    });

    test('rows carry the summary without replaying', () async {
      final done = play(MatchSetup.hotSeat(players: 2), 8, Random(2)).save;
      await store.put(done);
      final item = (await store.list()).single;
      expect(item.status, SaveStatus.ok);
      expect(item.openable, isTrue);
      expect(item.finished, isTrue);
      expect(item.moves, done.moves);
      expect(item.turnNumber, done.summary.turnNumber);
      expect(item.finishOrder, done.summary.finishOrder);
      expect(item.setup, done.setup);
      expect(item.name, done.name);
      expect(item.problem, isNull);
      expect(item.salvagedMoves, isNull);
    });
  });

  group('rename', () {
    test('changes the name and keeps updatedAt and the order', () async {
      await store.put(_save('a', 1));
      await store.put(_save('b', 2));
      expect(await store.rename('a', '  Friday  '), isTrue);
      final save = (await store.get('a'))!.save!;
      expect(save.name, 'Friday');
      expect(save.updatedAt, t0.add(const Duration(minutes: 1)));
      expect(save.log, _save('a', 1).log);
      final items = await store.list();
      expect(items.map((i) => i.id), ['b', 'a']);
      expect(items.last.name, 'Friday');
    });

    test('refuses a blank name, an unknown id', () async {
      await store.put(_save('a', 1));
      expect(await store.rename('a', '   '), isFalse);
      expect(await store.rename('a', ''), isFalse);
      expect(await store.rename('ghost', 'x'), isFalse);
      expect((await store.get('a'))!.save!.name, 'game a');
    });

    test('a long name is cut', () async {
      await store.put(_save('a', 1));
      await store.rename('a', 'y' * 90);
      expect((await store.get('a'))!.save!.name.length, maxSaveNameLength);
    });
  });

  group('delete', () {
    test('removes the save and reports whether it existed', () async {
      await store.put(_save('a', 1));
      await store.put(_save('b', 2));
      expect(await store.delete('a'), isTrue);
      expect(await store.get('a'), isNull);
      expect((await store.list()).map((i) => i.id), ['b']);
      expect(await store.delete('a'), isFalse);
      expect(await store.delete('ghost'), isFalse);
    });
  });

  group('damaged and incompatible rows', () {
    final good = _save('good', 3);

    test('unparsable text is listed greyed with the row\'s own name', () async {
      await store.put(good);
      store.putRaw(
        'junk',
        '{"schemaVe',
        name: 'Saturday',
        updatedAt: t0.add(const Duration(minutes: 10)),
      );
      final items = await store.list();
      expect(items.map((i) => i.id), ['junk', 'good']);
      final junk = items.first;
      expect(junk.status, SaveStatus.damaged);
      expect(junk.openable, isFalse);
      expect(junk.name, 'Saturday');
      expect(junk.updatedAt, t0.add(const Duration(minutes: 10)));
      expect(junk.problem, isNotEmpty);
      expect(junk.setup, isNull);
      expect(items.last.status, SaveStatus.ok);
    });

    test('a damaged row is not opened, not renamed, but deletable', () async {
      store.putRaw('junk', 'not json at all');
      final result = await store.get('junk');
      expect(result, isA<SaveDecodeFailed>());
      expect(result!.save, isNull);
      expect(result.failure!.problem, SaveProblem.notJson);
      expect(await store.rename('junk', 'Better'), isFalse);
      expect((await store.list()).single.name, 'junk');
      expect(await store.delete('junk'), isTrue);
      expect(await store.list(), isEmpty);
    });

    test('a newer schema is listed as incompatible', () async {
      final json = jsonDecode(SaveCodec.encode(good)) as Map<String, Object?>;
      json['schemaVersion'] = saveSchemaVersion + 3;
      store.putRaw('future', jsonEncode(json));
      final item = (await store.list()).single;
      expect(item.status, SaveStatus.incompatible);
      expect(item.openable, isFalse);
      expect(item.name, good.name);
      expect(await store.rename('future', 'x'), isFalse);
      expect(await store.delete('future'), isTrue);
    });

    test('a corrupt log is damaged but reports what can still be played',
        () async {
      final json = jsonDecode(SaveCodec.encode(good)) as Map<String, Object?>;
      final log = json['log'] as String;
      json['log'] = '${log.substring(0, 6)}zz${log.substring(8)}';
      store.putRaw('cut', jsonEncode(json));
      final item = (await store.list()).single;
      expect(item.status, SaveStatus.damaged);
      expect(item.salvagedMoves, 3);
      expect(item.name, good.name);
      final failure = (await store.get('cut'))!.failure!;
      expect(SaveReplayer.replay(failure.salvage!).applied, 3);
    });

    test('a damaged row never disturbs the others', () async {
      await store.put(good);
      store.putRaw('a', '');
      store.putRaw('b', '[]');
      store.putRaw('c', '{}');
      final items = await store.list();
      expect(items.length, 4);
      expect(items.where((i) => i.status == SaveStatus.ok).length, 1);
      expect((await store.get('good'))!.save, good);
    });

    test('putRaw defaults give a row that still lists', () async {
      store.putRaw('x', 'zzz');
      final item = (await store.list()).single;
      expect(item.name, 'x');
      expect(item.updatedAt.millisecondsSinceEpoch, 0);
    });
  });

  test('InMemorySaveStore is a SaveStore', () {
    expect(store, isA<SaveStore>());
  });
}
