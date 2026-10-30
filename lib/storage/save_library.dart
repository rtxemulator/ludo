import 'game_save.dart';
import 'save_replayer.dart';
import 'save_store.dart';
import 'save_write_queue.dart';

/// The outcome of opening one save: decoded and replayed.
class SaveCheck {
  const SaveCheck._(this.save, this.replay, this.problem);

  /// A save that decoded and replayed cleanly (it may be finished).
  const SaveCheck.good(GameSave save, SaveReplay replay)
      : this._(save, replay, null);

  /// A save that cannot be opened; [problem] says why.
  const SaveCheck.bad(String problem) : this._(null, null, problem);

  final GameSave? save;
  final SaveReplay? replay;
  final String? problem;

  bool get ok => save != null;

  /// Whether the game can be continued (replayed cleanly and not over).
  bool get resumable => replay?.resumable ?? false;
}

/// What the screens use: the store, its write queue, and lazy verification.
///
/// Reads wait for pending writes first, so a list never misses the move that
/// was just made. Verification (one replay per row) is memoised by
/// `id + updatedAt`.
class SaveLibrary {
  SaveLibrary(
    this.store, {
    void Function(Object error, StackTrace stack)? onError,
  }) : queue = SaveWriteQueue(store, onError: onError);

  final SaveStore store;
  final SaveWriteQueue queue;

  final Map<String, SaveCheck> _checks = {};

  /// Every save, newest first (see [SaveStore.list]), after pending writes.
  Future<List<SaveListItem>> list() async {
    await queue.flush();
    return store.list();
  }

  /// Decodes and replays [item]'s save. Never throws; the result is cached
  /// until the save changes (`updatedAt`) or is deleted.
  Future<SaveCheck> verify(SaveListItem item) async {
    if (item.status != SaveStatus.ok) {
      return SaveCheck.bad(item.problem ?? 'unreadable');
    }
    final key = _key(item);
    final cached = _checks[key];
    if (cached != null) {
      return cached;
    }
    await queue.flush();
    final SaveCheck check;
    try {
      final decoded = await store.get(item.id);
      final save = decoded?.save;
      if (save == null) {
        check = SaveCheck.bad(decoded?.failure?.message ?? 'missing');
      } else {
        final replay = SaveReplayer.replay(save);
        check = replay.ok
            ? SaveCheck.good(save, replay)
            : SaveCheck.bad(replay.failure!.message);
      }
    } on Object catch (e) {
      return SaveCheck.bad('$e');
    }
    _checks[key] = check;
    return check;
  }

  /// The most recently updated save that can be continued, or `null`.
  /// Rows that fail to replay are skipped.
  Future<GameSave?> lastResumable(List<SaveListItem> items) async {
    for (final item in items) {
      if (!item.openable || item.finished) {
        continue;
      }
      final check = await verify(item);
      if (check.resumable) {
        return check.save;
      }
    }
    return null;
  }

  /// Renames through the queue; `false` when refused.
  Future<bool> rename(String id, String name) async {
    final done = await queue.rename(id, name);
    return done;
  }

  /// Deletes through the queue.
  Future<bool> delete(String id) async {
    _checks.removeWhere((key, _) => key.startsWith('$id|'));
    return queue.delete(id);
  }

  String _key(SaveListItem item) =>
      '${item.id}|${item.updatedAt.millisecondsSinceEpoch}';
}
