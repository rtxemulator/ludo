import 'package:ludo/engine/ludo_engine.dart';

import 'fingerprint.dart';
import 'game_save.dart';

/// Why a replay stopped short.
enum ReplayProblem {
  /// The setup cannot start a match (fewer than two players).
  invalidSetup,

  /// The engine refused a log entry (wrong seat or die, illegal move, an
  /// entry after the game ended).
  entryRejected,

  /// Every entry applied but the final state is not the one the save
  /// recorded: the engine changed under the log, or the save was altered.
  checksumMismatch,
}

class ReplayFailure {
  const ReplayFailure(this.problem, this.index, this.message);

  final ReplayProblem problem;

  /// Number of entries that applied before the problem (the index of the
  /// rejected entry; the log length for a checksum mismatch).
  final int index;

  final String message;

  /// Whether the save is likely fine but no longer matches this engine.
  bool get incompatible => problem == ReplayProblem.checksumMismatch;

  @override
  String toString() => 'ReplayFailure(${problem.name} at $index: $message)';
}

/// Result of [SaveReplayer.replay].
class SaveReplay {
  const SaveReplay({
    required this.state,
    required this.applied,
    required this.total,
    this.failure,
  });

  /// The state after the [applied] entries that were valid; `null` only for
  /// [ReplayProblem.invalidSetup].
  final GameState? state;

  /// Entries applied.
  final int applied;

  /// Entries in the log.
  final int total;

  final ReplayFailure? failure;

  /// Every entry applied and the fingerprint (if any) matched.
  bool get ok => failure == null;

  /// Whether the game can be continued: replayed cleanly and not over.
  bool get resumable => ok && state != null && !state!.isOver;
}

/// Result of [SaveReplayer.timeline].
class SaveTimeline {
  const SaveTimeline(this.states, this.failure);

  /// `states[0]` is the start of the match, `states[k]` the state right
  /// after decision `k`.
  final List<GameState> states;

  final ReplayFailure? failure;

  /// Decisions applied.
  int get applied => states.isEmpty ? 0 : states.length - 1;
}

/// Rebuilds games from saves with `Engine.applyEntry` (the loop of
/// `Engine.replay`, with the failure point reported). Never throws.
abstract final class SaveReplayer {
  /// Replays [save]. Stops at the last valid entry and reports where and why
  /// it failed. With [verifyCheck] (default) a save that has a fingerprint
  /// must end in the state it recorded.
  static SaveReplay replay(GameSave save, {bool verifyCheck = true}) {
    final run = _run(save, null);
    var failure = run.failure;
    final state = run.state;
    if (failure == null && verifyCheck && state != null) {
      final check = save.check;
      if (check != null && check != StateFingerprint.of(state)) {
        failure = ReplayFailure(
          ReplayProblem.checksumMismatch,
          save.log.length,
          'the replay ends in a different state than the one saved',
        );
      }
    }
    return SaveReplay(
      state: state,
      applied: run.applied,
      total: save.log.length,
      failure: failure,
    );
  }

  /// Every intermediate state, for the replay viewer. The fingerprint is not
  /// checked; use [replay] for that.
  static SaveTimeline timeline(GameSave save) {
    final states = <GameState>[];
    final run = _run(save, states.add);
    return SaveTimeline(states, run.failure);
  }

  static ({GameState? state, int applied, ReplayFailure? failure}) _run(
    GameSave save,
    void Function(GameState state)? onState,
  ) {
    GameState state;
    try {
      state = save.setup.newGame(save.seed);
    } on Object catch (e) {
      return (
        state: null,
        applied: 0,
        failure: ReplayFailure(ReplayProblem.invalidSetup, 0, '$e'),
      );
    }
    onState?.call(state);
    for (var i = 0; i < save.log.length; i++) {
      try {
        state = Engine.applyEntry(state, save.log[i]);
      } on Object catch (e) {
        return (
          state: state,
          applied: i,
          failure: ReplayFailure(ReplayProblem.entryRejected, i, '$e'),
        );
      }
      onState?.call(state);
    }
    return (state: state, applied: save.log.length, failure: null);
  }
}
