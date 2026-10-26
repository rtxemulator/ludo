import 'package:ludo/ai/ai.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:test/test.dart';

import 'worker_test.dart' show positions;

/// A backend the test answers by hand.
class FakeBackend implements AiBackend {
  FakeBackend(this.sink);

  final AiResponseSink sink;
  final List<AiRequest> requests = [];
  bool closed = false;

  @override
  bool get alive => !closed;

  @override
  void send(AiRequest request) => requests.add(request);

  @override
  void close() => closed = true;
}

void main() {
  late GameState state;
  late List<Move> legal;
  late List<FakeBackend> backends;
  late AiTurnDriver driver;

  const think = 650.0;
  const greedy = GreedyBot();

  setUp(() {
    (state, legal) = positions(const RulesConfig()).first;
    backends = [];
    driver = AiTurnDriver(
      backend: (sink) {
        final backend = FakeBackend(sink);
        backends.add(backend);
        return backend;
      },
    );
  });

  void begin({double at = 0, AiLevel level = AiLevel.hard}) => driver.begin(
        nowMs: at,
        thinkMs: think,
        state: state,
        legal: legal,
        level: level,
      );

  /// The Hard move that is not the baseline bot's, so a test can tell which
  /// one was played.
  int notGreedy() {
    final g = legal.indexOf(greedy.choose(state, legal));
    return g == 0 ? 1 : 0;
  }

  test('the request goes out at once and carries the level and budget', () {
    begin(level: AiLevel.expert);
    final request = backends.single.requests.single;
    expect(request.id, driver.pendingId);
    expect(request.state, same(state));
    expect(request.legal, legal);
    expect(request.level, AiLevel.expert);
    expect(request.budgetMillis, 250);
  });

  test('a quick answer waits for the think time', () {
    begin();
    backends.single.sink(AiResponse(driver.pendingId!, notGreedy()));
    expect(driver.poll(10, state), isNull);
    expect(driver.poll(649, state), isNull);
    expect(driver.poll(650, state), legal[notGreedy()]);
    expect(driver.busy, isFalse);
    expect(driver.fallbackCount, 0);
  });

  test('a slower answer plays when it arrives, after the think time', () {
    driver = AiTurnDriver(
      backend: (sink) {
        final backend = FakeBackend(sink);
        backends.add(backend);
        return backend;
      },
    );
    driver.begin(
      nowMs: 0,
      thinkMs: 250, // reduced motion
      state: state,
      legal: legal,
      level: AiLevel.hard,
    );
    expect(driver.poll(250, state), isNull); // still computing
    expect(driver.poll(499, state), isNull);
    backends.single.sink(AiResponse(driver.pendingId!, notGreedy()));
    expect(driver.poll(500, state), legal[notGreedy()]);
  });

  test('Easy and forced moves never touch the worker', () {
    begin(level: AiLevel.easy);
    expect(backends, isEmpty);
    expect(driver.poll(think, state), greedy.choose(state, legal));

    driver.begin(
      nowMs: 0,
      thinkMs: think,
      state: state,
      legal: [legal.first],
      level: AiLevel.expert,
    );
    expect(backends, isEmpty);
    expect(driver.poll(think, state), legal.first);
  });

  group('stale answers', () {
    test('cancel drops the request; its late answer is ignored', () {
      begin();
      final oldId = driver.pendingId!;
      driver.cancel();
      expect(driver.busy, isFalse);
      expect(driver.poll(1000, state), isNull);

      begin(at: 1000);
      final newId = driver.pendingId!;
      expect(newId, isNot(oldId));
      // The abandoned turn's answer arrives and must not be played: the new
      // request is still open and, without an answer of its own, ends in the
      // baseline bot at the deadline.
      backends.single.sink(AiResponse(oldId, notGreedy()));
      expect(driver.poll(1100, state), isNull);
      expect(driver.busy, isTrue);
      expect(driver.poll(1000 + think, state), greedy.choose(state, legal));
      expect(driver.lastFallback, AiFallback.timeout);
    });

    test('only the answer with the current id is played', () {
      begin();
      final oldId = driver.pendingId!;
      driver.cancel();
      begin(at: 100);
      final newId = driver.pendingId!;
      final backend = backends.single;
      backend.sink(AiResponse(oldId, notGreedy()));
      backend
          .sink(AiResponse(newId, legal.indexOf(greedy.choose(state, legal))));
      expect(
        driver.poll(100 + think, state),
        greedy.choose(state, legal),
      );
    });

    test('a different state (new game, rewind) drops the request', () {
      begin();
      final other = Engine.newGame(seed: 99);
      backends.single.sink(AiResponse(driver.pendingId!, 0));
      expect(driver.poll(think, other), isNull);
      expect(driver.busy, isFalse);
      // The old answer can no longer be played either.
      expect(driver.poll(think, state), isNull);
    });

    test('an answer after the fallback is ignored', () {
      begin();
      final id = driver.pendingId!;
      expect(driver.poll(think, state), isNotNull); // watchdog: fallback
      backends.single.sink(AiResponse(id, notGreedy()));
      expect(driver.busy, isFalse);
      expect(driver.fallbackCount, 1);
    });
  });

  group('watchdog and fallback (D9)', () {
    test('a late worker: the baseline bot plays and the worker is replaced',
        () {
      begin();
      expect(driver.poll(think, state), greedy.choose(state, legal));
      expect(driver.fallbackCount, 1);
      expect(driver.lastFallback, AiFallback.timeout);
      expect(backends.single.closed, isTrue);
      expect(driver.hasBackend, isFalse);

      // The next request starts a fresh worker.
      begin(at: 2000);
      expect(backends, hasLength(2));
      expect(backends.last.requests, hasLength(1));
    });

    test(
        'nothing is played before the 600 ms deadline when the think time '
        'is shorter', () {
      driver.begin(
        nowMs: 0,
        thinkMs: 250,
        state: state,
        legal: legal,
        level: AiLevel.expert,
      );
      expect(driver.poll(599, state), isNull);
      expect(driver.poll(600, state), greedy.choose(state, legal));
      expect(driver.lastFallback, AiFallback.timeout);
    });

    test('a crashed worker: the baseline bot plays after the think time', () {
      begin();
      backends.single.sink(AiResponse.failed(driver.pendingId!));
      expect(driver.poll(100, state), isNull); // the think time still holds
      expect(driver.poll(think, state), greedy.choose(state, legal));
      expect(driver.lastFallback, AiFallback.crashed);
    });

    test('a dead worker is replaced on the next request', () {
      begin();
      backends.single
        ..closed = true
        ..sink(AiResponse.failed(driver.pendingId!));
      driver.poll(think, state);
      begin(at: 1000);
      expect(backends, hasLength(2));
      expect(backends.last.closed, isFalse);
    });

    for (final bad in [-1, 9999]) {
      test('an answer outside the legal list ($bad): the baseline bot plays',
          () {
        begin();
        backends.single.sink(AiResponse(driver.pendingId!, bad));
        expect(driver.poll(think, state), greedy.choose(state, legal));
        expect(driver.lastFallback, AiFallback.invalid);
        // A worker that answered is not replaced.
        expect(backends.single.closed, isFalse);
      });
    }

    test('the game never waits: polled every frame, a move arrives', () {
      // A worker that never answers, a 60 fps frame loop.
      var t = 0.0;
      begin();
      Move? move;
      while (move == null && t < 5000) {
        t += 16;
        move = driver.poll(t, state);
      }
      expect(move, isNotNull);
      expect(t, lessThanOrEqualTo(think + 16));
      expect(legal, contains(move));
    });
  });

  test('dispose shuts the worker down', () {
    begin();
    driver.dispose();
    expect(backends.single.closed, isTrue);
    expect(driver.busy, isFalse);
    expect(driver.hasBackend, isFalse);
  });

  test('warmUp starts the worker before the first request', () {
    driver.warmUp();
    expect(backends, hasLength(1));
    begin();
    expect(backends, hasLength(1)); // reused
  });

  test('the inline driver plays real moves deterministically', () {
    final a = AiTurnDriver.inline();
    final b = AiTurnDriver.inline();
    for (final level in [AiLevel.medium, AiLevel.hard, AiLevel.expert]) {
      a.begin(nowMs: 0, thinkMs: 0, state: state, legal: legal, level: level);
      b.begin(nowMs: 0, thinkMs: 0, state: state, legal: legal, level: level);
      final ma = a.poll(0, state);
      final mb = b.poll(0, state);
      expect(ma, isNotNull);
      expect(legal, contains(ma));
      expect(ma, mb);
    }
    expect(a.fallbackCount, 0);
  });
}
