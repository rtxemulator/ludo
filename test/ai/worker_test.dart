import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:ludo/ai/ai.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:test/test.dart';

/// Awaiting-move states with at least two legal moves under [rules].
List<(GameState, List<Move>)> positions(RulesConfig rules,
    {int games = 4, int every = 4, List<int> seats = const [0, 1, 2, 3]}) {
  final out = <(GameState, List<Move>)>[];
  for (var seed = 1; seed <= games; seed++) {
    final chooser = Random(seed);
    var state = Engine.newGame(seed: seed, rules: rules, activeSeats: seats);
    var n = 0;
    while (!state.isOver && n < 2000) {
      if (!state.awaitingMove) {
        state = Engine.roll(state).state;
        continue;
      }
      final moves = Engine.legalMoves(state);
      if (n++ % every == 0 && moves.length > 1) {
        out.add((state, moves));
      }
      state = Engine.apply(state, moves[chooser.nextInt(moves.length)]);
    }
  }
  return out;
}

/// Entry point that sends every request straight back.
void _echoEntry(SendPort toApp) {
  final inbox = ReceivePort();
  toApp.send(inbox.sendPort);
  inbox.listen((Object? message) => toApp.send(message));
}

/// Entry point that dies with an uncaught error on the first request.
void _crashEntry(SendPort toApp) {
  final inbox = ReceivePort();
  toApp.send(inbox.sendPort);
  inbox.listen((Object? message) {
    throw StateError('worker crashed');
  });
}

/// Entry point that never answers.
void _silentEntry(SendPort toApp) {
  final inbox = ReceivePort();
  toApp.send(inbox.sendPort);
  inbox.listen((Object? message) {});
}

/// Entry point that answers with an index outside the legal list.
void _badIndexEntry(SendPort toApp) {
  final inbox = ReceivePort();
  toApp.send(inbox.sendPort);
  inbox.listen((Object? message) {
    if (message is AiRequest) {
      toApp.send(AiResponse(message.id, message.legal.length + 5));
    }
  });
}

/// Sends [payload] to an echo isolate and returns what comes back.
Future<Object?> roundTrip(Object payload) async {
  final inbox = ReceivePort();
  final isolate = await Isolate.spawn<SendPort>(_echoEntry, inbox.sendPort);
  final events = StreamIterator<Object?>(inbox);
  try {
    await events.moveNext();
    final toWorker = events.current! as SendPort;
    toWorker.send(payload);
    await events.moveNext();
    return events.current;
  } finally {
    await events.cancel();
    isolate.kill(priority: Isolate.immediate);
  }
}

void main() {
  group('isolate round trip', () {
    test('GameState, RulesConfig and Move survive a port', () async {
      final (state, moves) = positions(const RulesConfig()).first;
      final back = await roundTrip((state, state.rules, moves));
      final (s, r, m) = back! as (GameState, RulesConfig, List<Move>);
      expect(s, state);
      expect(r, state.rules);
      expect(m, moves);
    });

    test('a banked-roll state with its TurnSnapshot survives a port', () async {
      const rules = RulesConfig(bankedRolls: true);
      var state = Engine.newGame(seed: 12, rules: rules);
      while (!state.awaitingMove) {
        state = Engine.roll(state).state;
      }
      expect(state.turnSnapshot, isNotNull);
      expect(state.bank, isNotEmpty);
      final snapshot = state.turnSnapshot!;
      final back = await roundTrip((state, snapshot));
      final (s, snap) = back! as (GameState, TurnSnapshot);
      expect(s, state);
      expect(snap, snapshot);
      expect(s.bank, state.bank);
    });

    test('team play and blockade options survive a port', () async {
      const rules = RulesConfig(
        blockades: true,
        blockadeMovement: true,
        blockadeCapture: true,
        teamsEnabled: true,
        bankedRolls: true,
      );
      final all = positions(rules, games: 6, every: 3);
      expect(all, isNotEmpty);
      for (final (state, moves) in all.take(12)) {
        final back = await roundTrip(
          AiRequest(
            id: 7,
            state: state,
            legal: moves,
            level: AiLevel.hard,
            budgetMillis: 100,
          ),
        );
        final request = back! as AiRequest;
        expect(request.id, 7);
        expect(request.state, state);
        expect(request.legal, moves);
        expect(request.level, AiLevel.hard);
        expect(request.budgetMillis, 100);
      }
    });

    test('responses survive a port', () async {
      final ok = await roundTrip(const AiResponse(3, 1)) as AiResponse;
      expect((ok.id, ok.index, ok.failed), (3, 1, false));
      final bad = await roundTrip(const AiResponse.failed(4)) as AiResponse;
      expect((bad.id, bad.index, bad.failed), (4, null, true));
    });
  });

  group('AiWorker', () {
    test('answers a request with an index into the legal list', () async {
      final answers = <AiResponse>[];
      final done = Completer<void>();
      final worker = AiWorker((r) {
        answers.add(r);
        done.complete();
      });
      addTearDown(worker.close);
      final (state, moves) = positions(const RulesConfig()).first;
      worker.send(
        AiRequest(
          id: 1,
          state: state,
          legal: moves,
          level: AiLevel.medium,
          budgetMillis: 40,
        ),
      );
      await done.future.timeout(const Duration(seconds: 20));
      expect(answers.single.id, 1);
      expect(answers.single.failed, isFalse);
      expect(answers.single.index, inInclusiveRange(0, moves.length - 1));
      expect(worker.alive, isTrue);
    });

    test('a crashing worker reports failure for the request in flight',
        () async {
      final answers = <AiResponse>[];
      final done = Completer<void>();
      final worker = AiWorker((r) {
        answers.add(r);
        done.complete();
      }, entry: _crashEntry);
      addTearDown(worker.close);
      final (state, moves) = positions(const RulesConfig()).first;
      worker.send(
        AiRequest(
          id: 9,
          state: state,
          legal: moves,
          level: AiLevel.hard,
          budgetMillis: 100,
        ),
      );
      await done.future.timeout(const Duration(seconds: 20));
      expect(answers.single.id, 9);
      expect(answers.single.failed, isTrue);
      expect(worker.alive, isFalse);
    });

    test('a closed worker answers nothing and fails new requests', () async {
      final answers = <AiResponse>[];
      final worker = AiWorker(answers.add, entry: _silentEntry)..close();
      expect(worker.alive, isFalse);
      final (state, moves) = positions(const RulesConfig()).first;
      worker.send(
        AiRequest(
          id: 2,
          state: state,
          legal: moves,
          level: AiLevel.medium,
          budgetMillis: 40,
        ),
      );
      expect(answers.single.failed, isTrue);
    });
  });

  group('AiTurnDriver with a real worker', () {
    // Wall-clock polling; a generous watchdog keeps a cold JIT isolate from
    // making this flaky. The frame-clock tests live in turn_driver_test.
    Future<Move?> play(AiTurnDriver driver, GameState state, List<Move> moves,
        AiLevel level) async {
      final clock = Stopwatch()..start();
      driver.begin(
        nowMs: 0,
        thinkMs: 0,
        state: state,
        legal: moves,
        level: level,
      );
      while (clock.elapsedMilliseconds < 15000) {
        final move = driver.poll(clock.elapsedMicroseconds / 1000, state);
        if (move != null) {
          return move;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return null;
    }

    test('Medium, Hard and Expert answer through the isolate', () async {
      final driver = AiTurnDriver(watchdogMs: 10000)..warmUp();
      addTearDown(driver.dispose);
      final (state, moves) = positions(const RulesConfig()).first;
      for (final level in [AiLevel.medium, AiLevel.hard, AiLevel.expert]) {
        final move = await play(driver, state, moves, level);
        expect(move, isNotNull, reason: level.name);
        expect(moves, contains(move), reason: level.name);
      }
      expect(driver.fallbackCount, 0);
    });

    test('a worker that never answers is replaced by the baseline bot',
        () async {
      var spawned = 0;
      final driver = AiTurnDriver(
        watchdogMs: 300,
        backend: (sink) {
          spawned++;
          return AiWorker(sink, entry: _silentEntry);
        },
      );
      addTearDown(driver.dispose);
      final (state, moves) = positions(const RulesConfig()).first;
      final move = await play(driver, state, moves, AiLevel.hard);
      expect(move, const GreedyBot().choose(state, moves));
      expect(driver.lastFallback, AiFallback.timeout);
      // The next request starts a fresh worker.
      driver.begin(
        nowMs: 0,
        thinkMs: 0,
        state: state,
        legal: moves,
        level: AiLevel.hard,
      );
      expect(spawned, 2);
    });

    test('a crashing worker falls back to the baseline bot at once', () async {
      final driver = AiTurnDriver(
        backend: (sink) => AiWorker(sink, entry: _crashEntry),
      );
      addTearDown(driver.dispose);
      final (state, moves) = positions(const RulesConfig()).first;
      final move = await play(driver, state, moves, AiLevel.expert);
      expect(move, const GreedyBot().choose(state, moves));
      expect(driver.lastFallback, AiFallback.crashed);
    });

    test('an answer outside the legal list falls back to the baseline bot',
        () async {
      final driver = AiTurnDriver(
        watchdogMs: 10000,
        backend: (sink) => AiWorker(sink, entry: _badIndexEntry),
      );
      addTearDown(driver.dispose);
      final (state, moves) = positions(const RulesConfig()).first;
      final move = await play(driver, state, moves, AiLevel.medium);
      expect(move, const GreedyBot().choose(state, moves));
      expect(driver.lastFallback, AiFallback.invalid);
    });
  });
}
