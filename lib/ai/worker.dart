import 'dart:async';
import 'dart:isolate';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';

import 'ai_player.dart';
import 'search.dart';

/// One decision to compute (`docs/ludo-ai.md` section 8).
///
/// Sent through an isolate port as is: [GameState], `RulesConfig`,
/// `TurnSnapshot` and [Move] are plain immutable classes (round trip proven
/// by `test/ai/worker_test.dart`).
class AiRequest {
  const AiRequest({
    required this.id,
    required this.state,
    required this.legal,
    required this.level,
    required this.budgetMillis,
  });

  /// Lets the caller drop answers that belong to an abandoned turn.
  final int id;
  final GameState state;

  /// What `Engine.legalMoves` gave for [state]; the answer indexes into it.
  final List<Move> legal;
  final AiLevel level;

  /// Wall-clock search budget (design doc D5).
  final int budgetMillis;
}

/// The worker's answer: the index of the chosen move in
/// [AiRequest.legal], or `null` when the worker could not answer
/// ([failed]).
class AiResponse {
  const AiResponse(this.id, this.index);
  const AiResponse.failed(this.id) : index = null;

  final int id;
  final int? index;

  bool get failed => index == null;
}

/// Receives every answer of a backend (including synthetic failures when a
/// worker dies with requests in flight).
typedef AiResponseSink = void Function(AiResponse response);

/// Something that computes [AiRequest]s: the real worker isolate, or an
/// in-process stand-in for tests.
abstract interface class AiBackend {
  /// `false` once the backend can no longer answer (crashed or closed).
  bool get alive;

  /// Queues [request]; the answer reaches the sink given at construction.
  void send(AiRequest request);

  /// Releases everything (kills the isolate). Idempotent.
  void close();
}

/// Builds a backend that reports to [sink].
typedef AiBackendFactory = AiBackend Function(AiResponseSink sink);

/// Default node budgets used by in-process backends in tests: the tournament
/// budgets of `docs/ludo-ai.md` section 11 (deterministic, no wall clock).
const Map<AiLevel, int> defaultNodeBudgets = {
  AiLevel.medium: 400,
  AiLevel.hard: 2500,
  AiLevel.expert: 8000,
};

/// Computes the answer to [request]. With [nodeBudgets] the search is limited
/// by node count (deterministic); otherwise by `request.budgetMillis`.
///
/// Never throws: any failure becomes [AiResponse.failed].
AiResponse answerRequest(
  AiRequest request, {
  Map<AiLevel, int>? nodeBudgets,
}) {
  try {
    final nodes = nodeBudgets?[request.level];
    final player = nodes != null
        ? AiPlayer.nodes(request.level, nodes)
        : AiPlayer(
            request.level,
            budget: AiBudget(maxMillis: request.budgetMillis),
          );
    final move = player.choose(request.state, request.legal);
    final index = request.legal.indexOf(move);
    return index < 0
        ? AiResponse.failed(request.id)
        : AiResponse(request.id, index);
  } on Object {
    return AiResponse.failed(request.id);
  }
}

/// Computes on the calling isolate, synchronously (the answer reaches the
/// sink before [send] returns). For tests, and as a no-isolate fallback.
class InlineAiBackend implements AiBackend {
  InlineAiBackend(this._sink, {this.nodeBudgets = defaultNodeBudgets});

  final AiResponseSink _sink;

  /// `null` searches by the request's wall-clock budget instead.
  final Map<AiLevel, int>? nodeBudgets;
  bool _closed = false;

  @override
  bool get alive => !_closed;

  @override
  void send(AiRequest request) {
    if (_closed) {
      _sink(AiResponse.failed(request.id));
      return;
    }
    _sink(answerRequest(request, nodeBudgets: nodeBudgets));
  }

  @override
  void close() => _closed = true;
}

/// Entry point of the worker isolate: hands its port to the app, then answers
/// every [AiRequest] in arrival order.
void aiWorkerMain(SendPort toApp) {
  final inbox = ReceivePort();
  toApp.send(inbox.sendPort);
  inbox.listen((Object? message) {
    if (message is AiRequest) {
      toApp.send(answerRequest(message));
    }
  });
}

/// One long-lived worker isolate (design doc section 8).
///
/// Spawning is asynchronous; requests sent meanwhile wait in a queue. If the
/// isolate dies (uncaught error, exit) every request in flight gets
/// [AiResponse.failed] and [alive] turns `false`.
class AiWorker implements AiBackend {
  AiWorker(this._sink, {void Function(SendPort) entry = aiWorkerMain}) {
    _inbox.listen(_onMessage);
    _errors.listen((_) => _die());
    _exits.listen((_) => _die());
    unawaited(_spawn(entry));
  }

  final AiResponseSink _sink;
  final ReceivePort _inbox = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final ReceivePort _exits = ReceivePort();
  final List<AiRequest> _queued = [];
  final Set<int> _inFlight = {};
  Isolate? _isolate;
  SendPort? _toWorker;
  bool _alive = true;

  @override
  bool get alive => _alive;

  Future<void> _spawn(void Function(SendPort) entry) async {
    try {
      final isolate = await Isolate.spawn<SendPort>(
        entry,
        _inbox.sendPort,
        onError: _errors.sendPort,
        onExit: _exits.sendPort,
        errorsAreFatal: true,
        debugName: 'ludo-ai',
      );
      if (_alive) {
        _isolate = isolate;
      } else {
        // Closed while spawning.
        isolate.kill(priority: Isolate.immediate);
      }
    } on Object {
      _die();
    }
  }

  void _onMessage(Object? message) {
    if (message is SendPort) {
      _toWorker = message;
      final queued = List<AiRequest>.of(_queued);
      _queued.clear();
      queued.forEach(_post);
    } else if (message is AiResponse) {
      if (_inFlight.remove(message.id)) {
        _sink(message);
      }
    }
  }

  void _post(AiRequest request) {
    try {
      _toWorker!.send(request);
    } on Object {
      // Not sendable: report it instead of waiting for the watchdog.
      if (_inFlight.remove(request.id)) {
        _sink(AiResponse.failed(request.id));
      }
    }
  }

  @override
  void send(AiRequest request) {
    if (!_alive) {
      _sink(AiResponse.failed(request.id));
      return;
    }
    _inFlight.add(request.id);
    if (_toWorker == null) {
      _queued.add(request);
    } else {
      _post(request);
    }
  }

  void _die() {
    if (!_alive) {
      return;
    }
    _alive = false;
    final lost = List<int>.of(_inFlight);
    _release();
    for (final id in lost) {
      _sink(AiResponse.failed(id));
    }
  }

  void _release() {
    _inFlight.clear();
    _queued.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _inbox.close();
    _errors.close();
    _exits.close();
  }

  @override
  void close() {
    if (!_alive) {
      return;
    }
    _alive = false;
    _release();
  }
}
