import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';

import 'ai_player.dart';
import 'worker.dart';

/// Why the driver played the baseline bot instead of the worker's answer.
enum AiFallback {
  /// No answer by the watchdog deadline.
  timeout,

  /// The worker died or reported a failure.
  crashed,

  /// The answer was not a member of the legal list.
  invalid,
}

class _Pending {
  _Pending({
    required this.id,
    required this.state,
    required this.legal,
    required this.sentMs,
    required this.dueMs,
  });

  final int id;
  final GameState state;
  final List<Move> legal;
  final double sentMs;
  final double dueMs;
  int? index;
  AiFallback? failure;
}

/// The small state machine behind an AI move (`docs/ludo-ai.md` section 8,
/// decision D9). Pure Dart and clock-free: the caller passes frame-clock
/// milliseconds, so the whole thing is testable without waiting.
///
/// Flow: [begin] sends the request at once; [poll] (every frame) returns the
/// move only after `max(think time, compute time)`. Answers carry an id, so
/// anything that belongs to an abandoned turn ([cancel], or a different
/// `state` passed to [poll]) is ignored. If the worker is late
/// ([watchdogMs]), dies, or answers with something not in the legal list, the
/// baseline `GreedyBot` plays instead, so the game never waits for the AI.
class AiTurnDriver {
  AiTurnDriver({
    AiBackendFactory? backend,
    this.watchdogMs = 600,
    Map<AiLevel, int> budgetMillis = AiPlayer.defaultMillis,
  })  : _factory = backend ?? ((sink) => AiWorker(sink)),
        _budgetMillis = budgetMillis;

  /// A driver that computes in process with node budgets (deterministic, no
  /// isolate). For tests.
  AiTurnDriver.inline({
    Map<AiLevel, int> nodeBudgets = defaultNodeBudgets,
  }) : this(
          backend: (sink) => InlineAiBackend(sink, nodeBudgets: nodeBudgets),
        );

  /// How long the worker may take before the baseline bot plays (ms).
  final double watchdogMs;

  final AiBackendFactory _factory;
  final Map<AiLevel, int> _budgetMillis;
  static const GreedyBot _greedy = GreedyBot();

  AiBackend? _backend;
  _Pending? _pending;
  int _nextId = 1;

  /// How many moves the baseline bot played instead of the worker, and why
  /// the last time.
  int fallbackCount = 0;
  AiFallback? lastFallback;

  /// Whether a request is open (sent and not yet played or cancelled).
  bool get busy => _pending != null;

  /// Id of the open request, if any.
  int? get pendingId => _pending?.id;

  /// Whether a worker currently exists.
  bool get hasBackend => _backend != null;

  AiBackend _ensureBackend() {
    var backend = _backend;
    if (backend == null || !backend.alive) {
      backend?.close();
      backend = _factory(_onResponse);
      _backend = backend;
    }
    return backend;
  }

  /// Starts the worker ahead of the first request (the first game with a
  /// searching AI seat), so the isolate is up before it is needed.
  void warmUp() => _ensureBackend();

  /// Opens a request for the move of the seat on turn. [thinkMs] is the
  /// readability pause: the move is never played sooner than that.
  void begin({
    required double nowMs,
    required double thinkMs,
    required GameState state,
    required List<Move> legal,
    required AiLevel level,
  }) {
    if (legal.isEmpty) {
      throw ArgumentError.value(legal, 'legal', 'no legal moves to choose');
    }
    final pending = _Pending(
      id: _nextId++,
      state: state,
      legal: legal,
      sentMs: nowMs,
      dueMs: nowMs + thinkMs,
    );
    _pending = pending;
    if (legal.length == 1) {
      pending.index = 0;
      return;
    }
    if (level == AiLevel.easy) {
      pending.index = legal.indexOf(_greedy.choose(state, legal));
      return;
    }
    _ensureBackend().send(
      AiRequest(
        id: pending.id,
        state: state,
        legal: legal,
        level: level,
        budgetMillis: _budgetMillis[level] ?? 100,
      ),
    );
  }

  void _onResponse(AiResponse response) {
    final pending = _pending;
    if (pending == null || response.id != pending.id) {
      return; // stale: belongs to an abandoned turn
    }
    if (pending.index != null || pending.failure != null) {
      return; // already settled (duplicate answer)
    }
    final index = response.index;
    if (index == null) {
      pending.failure = AiFallback.crashed;
    } else if (index < 0 || index >= pending.legal.length) {
      pending.failure = AiFallback.invalid;
    } else {
      pending.index = index;
    }
  }

  /// The move to play now, or `null` while the turn is not ready (think time
  /// running, or the worker still computing within the watchdog).
  ///
  /// [state] must be the state the request was made for; a different state
  /// means the turn was abandoned (new game, rewind), and the request is
  /// dropped.
  Move? poll(double nowMs, GameState state) {
    final pending = _pending;
    if (pending == null) {
      return null;
    }
    if (!identical(pending.state, state)) {
      _pending = null;
      return null;
    }
    if (nowMs < pending.dueMs) {
      return null;
    }
    final index = pending.index;
    if (index != null) {
      _pending = null;
      return pending.legal[index];
    }
    final overdue = nowMs - pending.sentMs >= watchdogMs;
    if (pending.failure == null && !overdue) {
      return null;
    }
    final reason = pending.failure ?? AiFallback.timeout;
    _pending = null;
    fallbackCount++;
    lastFallback = reason;
    if (reason == AiFallback.timeout) {
      // A worker that is still busy would delay every later answer too:
      // replace it with a fresh one on the next request.
      _backend?.close();
      _backend = null;
    }
    return _greedy.choose(pending.state, pending.legal);
  }

  /// Drops the open request (new game, rewind, menu, leaving the table); a
  /// late answer for it is ignored by id.
  void cancel() {
    _pending = null;
  }

  /// Cancels and shuts the worker down.
  void dispose() {
    _pending = null;
    _backend?.close();
    _backend = null;
  }
}
