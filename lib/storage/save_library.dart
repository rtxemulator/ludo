import 'game_save.dart';
import 'replay_script.dart';
import 'save_replayer.dart';
import 'save_store.dart';
import 'save_write_queue.dart';

/// The outcome of opening one save: decoded and replayed.
class SaveCheck {
  const SaveCheck._(this.save, this.replay, this.problem, this.partialMoves);

  /// A save that decoded and replayed cleanly (it may be finished).
  const SaveCheck.good(GameSave save, SaveReplay replay)
      : this._(save, replay, null, 0);

  /// A save that cannot be opened; [problem] says why. [partialMoves] is how
  /// many decisions still replay before the engine refused one (the viewer
  /// can play those).
  const SaveCheck.bad(String problem, {int partialMoves = 0})
      : this._(null, null, problem, partialMoves);

  final GameSave? save;
  final SaveReplay? replay;
  final String? problem;

  /// For a save that cannot be opened: decisions that still replay (`0`
  /// when none, or when the replay cannot be trusted at all).
  final int partialMoves;

  bool get ok => save != null;

  /// Whether the game can be continued (replayed cleanly and not over).
  bool get resumable => replay?.resumable ?? false;
}

/// The outcome of opening one save for the replay viewer.
class ReplayOpening {
  const ReplayOpening._(this.script, this.salvaged, this.problem);

  /// A save that can be played, whole or in part.
  const ReplayOpening.ready(ReplayScript script, {bool salvaged = false})
      : this._(script, salvaged, null);

  /// A save with nothing to replay; [problem] says why.
  const ReplayOpening.refused(String problem) : this._(null, false, problem);

  /// What the viewer plays; `null` when refused.
  final ReplayScript? script;

  /// Whether the file was damaged and only its readable start is played.
  final bool salvaged;

  final String? problem;

  bool get ok => script != null;

  /// Whether the replay stops before the game did (a damaged log, or an
  /// entry the engine refused): the viewer says so.
  bool get partial => salvaged || (script?.partial ?? false);

  /// Decisions the viewer can play.
  int get playable => script?.length ?? 0;

  /// Opens [save] as it is in memory (the game just played). A save whose
  /// final state does not match its fingerprint is refused, like a row that
  /// fails verification; one with an entry the engine rejects replays up to
  /// that entry.
  static ReplayOpening of(GameSave save, {bool salvaged = false}) {
    if (!salvaged) {
      final failure = SaveReplayer.replay(save).failure;
      if (failure != null && failure.incompatible) {
        return ReplayOpening.refused(failure.message);
      }
    }
    final script = ReplayScript.of(save);
    if (!script.hasMoves) {
      return const ReplayOpening.refused('there is nothing to replay');
    }
    return ReplayOpening.ready(script, salvaged: salvaged);
  }
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
        final failure = replay.failure;
        check = failure == null
            ? SaveCheck.good(save, replay)
            : SaveCheck.bad(
                failure.message,
                partialMoves: failure.problem == ReplayProblem.entryRejected
                    ? replay.applied
                    : 0,
              );
      }
    } on Object catch (e) {
      return SaveCheck.bad('$e');
    }
    _checks[key] = check;
    return check;
  }

  /// Opens [item] for the replay viewer: any readable save (finished or in
  /// progress), and a damaged one up to its last valid entry. Waits for
  /// pending writes first and then reads the stored row, so it never sees a
  /// half-written log (a write replaces the whole row). Never throws.
  Future<ReplayOpening> openReplay(SaveListItem item) async {
    try {
      await queue.flush();
      final decoded = await store.get(item.id);
      if (decoded == null) {
        return const ReplayOpening.refused('missing');
      }
      final whole = decoded.save;
      if (whole != null) {
        return ReplayOpening.of(whole);
      }
      final salvage = decoded.failure?.salvage;
      if (salvage == null) {
        return ReplayOpening.refused(decoded.failure?.message ?? 'unreadable');
      }
      return ReplayOpening.of(salvage, salvaged: true);
    } on Object catch (e) {
      return ReplayOpening.refused('$e');
    }
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
