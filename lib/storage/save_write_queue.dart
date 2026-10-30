import 'dart:async';

import 'game_save.dart';
import 'save_store.dart';

/// Serialises every write to a [SaveStore], one lane per save id.
///
/// Every `put` holds the full log, so an older write must never land after a
/// newer one. Within a lane operations run strictly one at a time, in the
/// order they were made; different saves do not wait for each other. A `put`
/// queued behind a running operation replaces an earlier `put` that has not
/// started yet (the newer one holds everything the older one did), so a slow
/// store never builds a backlog.
///
/// Callers never wait: [put] returns at once and a failure is reported
/// through [errors] (and [onError]) instead of being thrown. The next write
/// heals a lost one because it carries the whole log. [flush] completes when
/// every lane is idle.
class SaveWriteQueue {
  SaveWriteQueue(this.store, {this.onError});

  final SaveStore store;

  /// Called for every failed operation.
  final void Function(Object error, StackTrace stack)? onError;

  final Map<String, _Lane> _lanes = {};
  final List<Completer<void>> _idleWaiters = [];
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  /// Failed operations (the error objects).
  Stream<Object> get errors => _errors.stream;

  /// Whether nothing is queued or running.
  bool get idle => _lanes.isEmpty;

  /// Queues [save] to be stored (insert or replace).
  void put(GameSave save) => _schedule(save.id, _PutOp(save));

  /// Queues a rename; completes with the store's answer (`false` when it
  /// refused or failed).
  Future<bool> rename(String id, String name) {
    final op = _RenameOp(id, name);
    _schedule(id, op);
    return op.result.future;
  }

  /// Queues a delete; completes with the store's answer (`false` when the id
  /// was unknown or the operation failed).
  Future<bool> delete(String id) {
    final op = _DeleteOp(id);
    _schedule(id, op);
    return op.result.future;
  }

  /// Completes when every operation queued so far (and any queued while
  /// waiting) has finished.
  Future<void> flush() async {
    while (_lanes.isNotEmpty) {
      final waiter = Completer<void>();
      _idleWaiters.add(waiter);
      await waiter.future;
    }
  }

  void _schedule(String id, _Op op) {
    final lane = _lanes.putIfAbsent(id, _Lane.new);
    if (op is _PutOp && lane.ops.isNotEmpty && lane.ops.last is _PutOp) {
      lane.ops[lane.ops.length - 1] = op;
    } else {
      lane.ops.add(op);
    }
    if (!lane.running) {
      lane.running = true;
      unawaited(_drain(id, lane));
    }
  }

  Future<void> _drain(String id, _Lane lane) async {
    while (lane.ops.isNotEmpty) {
      final op = lane.ops.removeAt(0);
      try {
        await op.run(store);
      } on Object catch (error, stack) {
        op.fail();
        _errors.add(error);
        onError?.call(error, stack);
      }
    }
    lane.running = false;
    _lanes.remove(id);
    final waiting = List<Completer<void>>.of(_idleWaiters);
    _idleWaiters.clear();
    for (final waiter in waiting) {
      waiter.complete();
    }
  }

  /// Closes the error stream. Pending operations still finish.
  Future<void> close() => _errors.close();
}

class _Lane {
  final List<_Op> ops = [];
  bool running = false;
}

abstract class _Op {
  Future<void> run(SaveStore store);

  /// Called when [run] threw.
  void fail() {}
}

class _PutOp extends _Op {
  _PutOp(this.save);

  final GameSave save;

  @override
  Future<void> run(SaveStore store) => store.put(save);
}

class _RenameOp extends _Op {
  _RenameOp(this.id, this.name);

  final String id;
  final String name;
  final Completer<bool> result = Completer<bool>();

  @override
  Future<void> run(SaveStore store) async {
    result.complete(await store.rename(id, name));
  }

  @override
  void fail() {
    if (!result.isCompleted) {
      result.complete(false);
    }
  }
}

class _DeleteOp extends _Op {
  _DeleteOp(this.id);

  final String id;
  final Completer<bool> result = Completer<bool>();

  @override
  Future<void> run(SaveStore store) async {
    result.complete(await store.delete(id));
  }

  @override
  void fail() {
    if (!result.isCompleted) {
      result.complete(false);
    }
  }
}
