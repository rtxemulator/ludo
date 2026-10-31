import 'dart:async';
import 'dart:math';

import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

import 'storage_helpers.dart';

/// A store whose operations finish only when the test says so, and that
/// records the order in which they started and finished.
class _GatedStore implements SaveStore {
  final InMemorySaveStore inner = InMemorySaveStore();
  final List<String> events = [];
  final List<Completer<void>> gates = [];
  bool failNext = false;

  Future<void> _gate(String label) async {
    events.add('start $label');
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    if (failNext) {
      failNext = false;
      events.add('fail $label');
      throw StateError('disk full');
    }
    events.add('end $label');
  }

  /// Opens the oldest gate.
  void release() => gates.removeAt(0).complete();

  @override
  Future<void> put(GameSave save) async {
    await _gate('put ${save.id} ${save.moves}');
    await inner.put(save);
  }

  @override
  Future<bool> rename(String id, String name) async {
    await _gate('rename $id');
    return inner.rename(id, name);
  }

  @override
  Future<bool> delete(String id) async {
    await _gate('delete $id');
    return inner.delete(id);
  }

  @override
  Future<SaveDecode?> get(String id) => inner.get(id);

  @override
  Future<List<SaveListItem>> list() => inner.list();
}

GameSave _game(String id, int moves) {
  final played = play(
    MatchSetup.hotSeat(players: 2),
    id.hashCode & 0xffff,
    Random(1),
    maxDecisions: moves,
  );
  final b = played.save;
  return GameSave(
    id: id,
    name: id,
    createdAt: t0,
    updatedAt: b.updatedAt,
    setup: b.setup,
    seed: b.seed,
    log: b.log,
    summary: b.summary,
    check: b.check,
  );
}

Future<void> _spin() => Future<void>.delayed(Duration.zero);

void main() {
  test('writes of one save run one at a time, in order', () async {
    final store = _GatedStore();
    final queue = SaveWriteQueue(store);
    queue.put(_game('a', 1));
    await _spin();
    expect(store.events, ['start put a 1']);

    // The first write is still running; the next ones wait.
    queue.put(_game('a', 2));
    await _spin();
    expect(store.events, ['start put a 1']);

    store.release();
    await _spin();
    expect(store.events, [
      'start put a 1',
      'end put a 1',
      'start put a 2',
    ]);
    store.release();
    await queue.flush();
    expect((await store.inner.get('a'))!.save!.moves, 2);
  });

  test('a put queued behind a running write replaces an unstarted put',
      () async {
    final store = _GatedStore();
    final queue = SaveWriteQueue(store);
    queue.put(_game('a', 1));
    await _spin();
    queue.put(_game('a', 2));
    queue.put(_game('a', 3));
    queue.put(_game('a', 4));
    store.release();
    await _spin();
    store.release();
    await queue.flush();
    // 1 ran, 2 and 3 were superseded, 4 landed last.
    expect(store.events.where((e) => e.startsWith('start')).toList(),
        ['start put a 1', 'start put a 4']);
    expect((await store.inner.get('a'))!.save!.moves, 4);
  });

  test('different saves do not wait for each other', () async {
    final store = _GatedStore();
    final queue = SaveWriteQueue(store);
    queue.put(_game('a', 1));
    queue.put(_game('b', 1));
    await _spin();
    expect(store.events, ['start put a 1', 'start put b 1']);
    store.release();
    store.release();
    await queue.flush();
    expect(queue.idle, isTrue);
  });

  test('rename and delete wait for the writes before them', () async {
    final store = _GatedStore();
    final queue = SaveWriteQueue(store);
    queue.put(_game('a', 2));
    final renamed = queue.rename('a', 'Nice game');
    await _spin();
    expect(store.events, ['start put a 2']);
    store.release();
    await _spin();
    store.release();
    expect(await renamed, isTrue);
    expect((await store.inner.get('a'))!.save!.name, 'Nice game');

    final deleted = queue.delete('a');
    await _spin();
    store.release();
    expect(await deleted, isTrue);
    expect(await store.inner.get('a'), isNull);
  });

  test('a failed write is reported, does not block, and is healed by the next',
      () async {
    final store = _GatedStore();
    final seen = <Object>[];
    final queue = SaveWriteQueue(store, onError: (e, _) => seen.add(e));
    final streamed = <Object>[];
    final sub = queue.errors.listen(streamed.add);

    store.failNext = true;
    queue.put(_game('a', 1));
    await _spin();
    queue.put(_game('a', 2));
    store.release();
    await _spin();
    store.release();
    await queue.flush();

    expect(seen, hasLength(1));
    await _spin();
    expect(streamed, hasLength(1));
    expect((await store.inner.get('a'))!.save!.moves, 2);
    await sub.cancel();
    await queue.close();
  });

  test('a failed rename completes with false', () async {
    final store = _GatedStore();
    final queue = SaveWriteQueue(store);
    store.failNext = true;
    final renamed = queue.rename('a', 'x');
    await _spin();
    store.release();
    expect(await renamed, isFalse);
    await queue.flush();
    expect(queue.idle, isTrue);
  });

  test('flush completes at once when idle and waits for late writes', () async {
    final store = _GatedStore();
    final queue = SaveWriteQueue(store);
    await queue.flush();

    queue.put(_game('a', 1));
    var flushed = false;
    final done = queue.flush().then((_) => flushed = true);
    await _spin();
    expect(flushed, isFalse);
    store.release();
    await done;
    expect(flushed, isTrue);
  });
}
