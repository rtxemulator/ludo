import 'dart:convert';
import 'dart:math';

import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

import 'storage_helpers.dart';

GameSave _save(String id, int minute, {int moves = 6, int seed = 11}) {
  final played = play(
    MatchSetup.hotSeat(players: 2),
    seed,
    Random(seed),
    maxDecisions: moves,
  );
  final b = played.save;
  return GameSave(
    id: id,
    name: 'game $id',
    createdAt: t0,
    updatedAt: t0.add(Duration(minutes: minute)),
    setup: b.setup,
    seed: b.seed,
    log: b.log,
    finished: b.finished,
    summary: b.summary,
    check: b.check,
  );
}

void main() {
  late InMemorySaveStore store;
  late SaveLibrary library;
  setUp(() {
    store = InMemorySaveStore();
    library = SaveLibrary(store);
  });

  test('list waits for pending writes', () async {
    library.queue.put(_save('a', 1));
    library.queue.put(_save('b', 2));
    final items = await library.list();
    expect(items.map((i) => i.id), ['b', 'a']);
  });

  test('verify replays a good save and caches the answer', () async {
    await store.put(_save('a', 1));
    final item = (await library.list()).single;
    final first = await library.verify(item);
    expect(first.ok, isTrue);
    expect(first.resumable, isTrue);
    expect(identical(await library.verify(item), first), isTrue);
  });

  test('verify marks a changed log as bad (flipped fingerprint)', () async {
    final good = _save('a', 1);
    final json = jsonDecode(SaveCodec.encode(good)) as Map<String, Object?>;
    json['check'] = '0000000000000000';
    store.putRaw('a', jsonEncode(json),
        name: 'game a', updatedAt: good.updatedAt);
    final item = (await library.list()).single;
    expect(item.status, SaveStatus.ok); // list only decodes
    final check = await library.verify(item);
    expect(check.ok, isFalse);
    expect(check.problem, isNotNull);
  });

  test('verify of a damaged or newer row is bad without a replay', () async {
    store.putRaw('junk', '{{{', name: 'junk');
    final item = (await library.list()).single;
    expect(item.openable, isFalse);
    final check = await library.verify(item);
    expect(check.ok, isFalse);
  });

  test('a finished save verifies but is not resumable', () async {
    final played = play(MatchSetup.hotSeat(players: 2), 5, Random(5));
    expect(played.last.isOver, isTrue);
    await store.put(played.save);
    final item = (await library.list()).single;
    expect(item.finished, isTrue);
    final check = await library.verify(item);
    expect(check.ok, isTrue);
    expect(check.resumable, isFalse);
    expect(await library.lastResumable([item]), isNull);
  });

  test('lastResumable picks the newest unfinished readable save', () async {
    final finished = play(MatchSetup.hotSeat(players: 2), 5, Random(5)).save;
    await store.put(GameSave(
      id: 'done',
      name: 'done',
      createdAt: t0,
      updatedAt: t0.add(const Duration(minutes: 30)),
      setup: finished.setup,
      seed: finished.seed,
      log: finished.log,
      finished: true,
      summary: finished.summary,
      check: finished.check,
    ));
    store.putRaw('junk', 'nope',
        name: 'junk', updatedAt: t0.add(const Duration(minutes: 20)));
    final bad = jsonDecode(SaveCodec.encode(_save('drift', 10)))
        as Map<String, Object?>;
    bad['check'] = 'ffffffffffffffff';
    store.putRaw('drift', jsonEncode(bad),
        name: 'drift', updatedAt: t0.add(const Duration(minutes: 10)));
    await store.put(_save('old', 3));
    await store.put(_save('older', 2));

    final items = await library.list();
    final pick = await library.lastResumable(items);
    expect(pick?.id, 'old');
  });

  test('lastResumable is null with nothing to continue', () async {
    expect(await library.lastResumable(await library.list()), isNull);
  });

  test('rename and delete go through the queue', () async {
    await store.put(_save('a', 1));
    expect(await library.rename('a', '  Friday  '), isTrue);
    expect((await library.list()).single.name, 'Friday');
    expect(await library.rename('a', '   '), isFalse);
    expect(await library.rename('zzz', 'x'), isFalse);
    expect(await library.delete('a'), isTrue);
    expect(await library.list(), isEmpty);
    expect(await library.delete('a'), isFalse);
  });

  test('a rename keeps updatedAt, so the cached check stays valid', () async {
    await store.put(_save('a', 1));
    final before = (await library.list()).single;
    final check = await library.verify(before);
    await library.rename('a', 'new');
    final after = (await library.list()).single;
    expect(after.updatedAt, before.updatedAt);
    expect(identical(await library.verify(after), check), isTrue);
  });
}
