import 'package:ludo/engine/ludo_engine.dart';

import 'fingerprint.dart';
import 'game_save.dart';
import 'save_replayer.dart';

/// One decision of a replay, ready to be played by the viewer.
class ReplayStep {
  const ReplayStep({
    required this.index,
    required this.entry,
    required this.before,
    required this.ready,
    required this.move,
    required this.after,
  });

  /// 1-based number of the decision (`1..length`).
  final int index;

  /// The log entry: who rolled, which face, which token.
  final MoveLogEntry entry;

  /// The state after the previous decision (the start of the match for the
  /// first one).
  final GameState before;

  /// [before] with the roll for this decision made (and any passes in
  /// between applied): a die pending, or with banked rolls the bank to spend.
  /// This is what the table shows just before the token hops.
  final GameState ready;

  /// The move the entry stands for, legal in [ready].
  final Move move;

  /// The state right after the decision (`Engine.apply(ready, move)`).
  final GameState after;

  /// Whether the board differs between [before] and [ready]. It only does
  /// when banked rolls reverted a turn (a dead end) between the two
  /// decisions: the tokens went back to where that turn began.
  bool get revertedBefore => !_sameBoard(before, ready);

  /// The seat that rolled (the one whose turn it is).
  int get roller => entry.seat;

  /// The face of the die that was played.
  int get dice => entry.dice;
}

bool _sameBoard(GameState a, GameState b) {
  for (var seat = 0; seat < a.tokens.length; seat++) {
    for (var i = 0; i < a.tokens[seat].length; i++) {
      if (a.tokens[seat][i] != b.tokens[seat][i]) {
        return false;
      }
    }
  }
  return true;
}

/// Everything the replay viewer needs from a save, computed once: the state
/// after each decision (the same list as [SaveReplayer.timeline]) and, for
/// each decision, the state just before it and the move that was made.
///
/// Never throws. A log that stops being valid (or does not match the engine
/// any more) gives a shorter script and a [failure].
class ReplayScript {
  ReplayScript._(this.save, this.states, this._steps, this.failure);

  /// Builds the script of [save]. Stops at the last valid entry.
  factory ReplayScript.of(GameSave save) {
    final timeline = SaveReplayer.timeline(save);
    final states = timeline.states;
    final steps = <ReplayStep>[];
    for (var k = 1; k < states.length; k++) {
      final built = _stepFor(k, save.log[k - 1], states[k - 1], states[k]);
      if (built == null) {
        // Cannot happen for a timeline that applied; refuse to show a game
        // that disagrees with itself rather than throw.
        return ReplayScript._(
          save,
          states.sublist(0, k),
          steps,
          ReplayFailure(
            ReplayProblem.entryRejected,
            k - 1,
            'decision $k could not be rebuilt',
          ),
        );
      }
      steps.add(built);
    }
    return ReplayScript._(save, states, steps, timeline.failure);
  }

  /// The save this script plays (for a salvage: the valid part).
  final GameSave save;

  /// `states[0]` is the start of the match, `states[k]` the state right after
  /// decision `k`.
  final List<GameState> states;

  final List<ReplayStep> _steps;

  /// Why the script is shorter than the log, if it is.
  final ReplayFailure? failure;

  /// Number of decisions that can be played (`N`).
  int get length => _steps.length;

  /// Decisions in the log, including ones that could not be played.
  int get logLength => save.log.length;

  /// Whether the script stops before the end of the log.
  bool get partial => failure != null;

  /// Whether there is at least one decision to play.
  bool get hasMoves => _steps.isNotEmpty;

  /// Decision [k] (`1..length`).
  ReplayStep step(int k) => _steps[k - 1];

  /// The state shown at position [k]: after decision [k] (`0` is the start).
  GameState at(int k) => states[k];

  /// Whether the last state is the end of a game.
  bool get endsInGameOver => states.isNotEmpty && states.last.isOver;

  static ReplayStep? _stepFor(
    int k,
    MoveLogEntry entry,
    GameState before,
    GameState after,
  ) {
    try {
      final ready = before.awaitingMove ? before : Engine.nextDecision(before);
      if (ready.isOver) {
        return null;
      }
      final Iterable<Move> moves;
      if (ready.rules.bankedRolls) {
        moves = Engine.legalMoves(ready).where(
          (m) =>
              m.tokenIndex == entry.tokenIndex &&
              m.isUnit == entry.unit &&
              ready.bank[m.dieIndex] == entry.dice,
        );
      } else {
        moves = Engine.legalMoves(ready).where(
          (m) => m.tokenIndex == entry.tokenIndex && m.isUnit == entry.unit,
        );
      }
      if (moves.isEmpty) {
        return null;
      }
      final move = moves.first;
      final applied = Engine.apply(ready, move);
      if (StateFingerprint.of(applied) != StateFingerprint.of(after)) {
        return null;
      }
      return ReplayStep(
        index: k,
        entry: entry,
        before: before,
        ready: ready,
        move: move,
        after: after,
      );
    } on Object {
      return null;
    }
  }
}
