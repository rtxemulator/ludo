import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/ai/ai.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/ui/core/motion_spec.dart';

import 'package:ludo_app/game/game_controller.dart';

/// A worker stand-in the test controls: it records every request and lets
/// the test decide when (and whether) to answer.
class ScriptedBackend implements AiBackend {
  ScriptedBackend(this.sink, this.onRequest);

  final AiResponseSink sink;
  final void Function(ScriptedBackend backend, AiRequest request) onRequest;
  final List<AiRequest> requests = [];
  bool closed = false;

  @override
  bool get alive => !closed;

  @override
  void send(AiRequest request) {
    requests.add(request);
    onRequest(this, request);
  }

  @override
  void close() => closed = true;
}

/// The Medium / Hard / Expert seats go through the worker; a controller wired
/// to scripted backends with a fake frame clock steps in 16 ms frames.
class Rig {
  Rig({
    required this.onRequest,
    AiLevel level = AiLevel.medium,
    int players = 2,
    RulesConfig rules = const RulesConfig(),
    bool reduced = false,
    int seed = 8,
  }) {
    var setup = MatchSetup.hotSeat(players: players, rules: rules);
    for (final seat in setup.activeSeats) {
      setup = setup.withSeat(seat, SeatConfig.ai(level: level));
    }
    driver = AiTurnDriver(
      backend: (sink) {
        final backend = ScriptedBackend(sink, onRequest);
        backends.add(backend);
        return backend;
      },
    );
    game = GameController(
      setup: setup,
      seed: seed,
      now: () => t,
      haptics: false,
      aiDriver: driver,
    );
    if (reduced) {
      game.spec = MotionSpec.reduced;
    }
  }

  final void Function(ScriptedBackend backend, AiRequest request) onRequest;
  final List<ScriptedBackend> backends = [];
  late final AiTurnDriver driver;
  late final GameController game;
  double t = 0;

  int get requestCount => backends.fold(0, (n, b) => n + b.requests.length);

  AiRequest get lastRequest =>
      backends.lastWhere((b) => b.requests.isNotEmpty).requests.last;

  void step() {
    t += 16;
    game.tick();
  }

  /// Steps until [done] (or [maxFrames]); returns whether it became true.
  bool until(bool Function() done, {int maxFrames = 100000}) {
    for (var i = 0; i < maxFrames; i++) {
      if (done()) {
        return true;
      }
      step();
    }
    return done();
  }

  /// Steps until the worker has been asked for a move (needs a choice with
  /// at least two legal moves).
  void untilAsked() {
    final before = requestCount;
    expect(until(() => requestCount > before), isTrue);
  }
}

void main() {
  test('Easy seats never use the worker', () {
    final rig = Rig(level: AiLevel.easy, onRequest: (b, r) {})
      ..game.spec = MotionSpec.reduced;
    expect(
      rig.until(() => rig.game.phase == GamePhase.gameOver, maxFrames: 400000),
      isTrue,
    );
    expect(rig.backends, isEmpty);
    rig.game.dispose();
  });

  test('a searching level warms the worker up with the game', () {
    final rig = Rig(onRequest: (b, r) {});
    expect(rig.backends, hasLength(1));
    rig.game.dispose();
    expect(rig.backends.single.closed, isTrue);
  });

  for (final level in [AiLevel.medium, AiLevel.hard, AiLevel.expert]) {
    test('${level.name}: the request carries the level and its time budget',
        () {
      final rig = Rig(
        level: level,
        onRequest: (b, r) => b.sink(AiResponse(r.id, 0)),
      );
      rig.untilAsked();
      final request = rig.lastRequest;
      expect(request.level, level);
      expect(request.budgetMillis, AiPlayer.defaultMillis[level]);
      expect(request.legal.length, greaterThan(1));
      expect(request.state, same(rig.game.state));
      rig.game.dispose();
    });
  }

  test('a quick answer still waits for the think delay', () {
    final rig = Rig(onRequest: (b, r) => b.sink(AiResponse(r.id, 0)));
    rig.untilAsked();
    final asked = rig.t;
    expect(rig.game.phase, GamePhase.awaitingMove);
    while (rig.t - asked < GameController.aiMoveDelayMs - 20) {
      rig.step();
      expect(rig.game.phase, GamePhase.awaitingMove);
    }
    expect(
      rig.until(() => rig.game.phase == GamePhase.moving, maxFrames: 20),
      isTrue,
    );
    expect(rig.t - asked, greaterThanOrEqualTo(GameController.aiMoveDelayMs));
    rig.game.dispose();
  });

  test('a slower answer plays when it arrives, not before', () {
    // Reduced motion: think delay 250 ms, the search takes 450 ms.
    late AiRequest pending;
    late ScriptedBackend source;
    final rig = Rig(
      reduced: true,
      onRequest: (b, r) {
        pending = r;
        source = b;
      },
    );
    rig.untilAsked();
    final asked = rig.t;
    while (rig.t - asked < 450) {
      rig.step();
      expect(rig.game.phase, GamePhase.awaitingMove);
    }
    source.sink(AiResponse(pending.id, pending.legal.length - 1));
    rig.step();
    expect(rig.game.phase, GamePhase.moving);
    expect(rig.driver.fallbackCount, 0);
    rig.game.dispose();
  });

  group('watchdog and fallback (D9)', () {
    test('a late worker: the baseline bot plays at the deadline', () {
      final rig = Rig(onRequest: (b, r) {}); // never answers
      rig.untilAsked();
      final asked = rig.t;
      expect(
        rig.until(() => rig.game.phase == GamePhase.moving, maxFrames: 100),
        isTrue,
      );
      expect(rig.t - asked, greaterThanOrEqualTo(600));
      expect(rig.t - asked, lessThan(700));
      expect(rig.driver.fallbackCount, 1);
      expect(rig.driver.lastFallback, AiFallback.timeout);
      // The stuck worker was replaced.
      expect(rig.backends.first.closed, isTrue);
      rig.game.dispose();
    });

    test('a crashed worker: the baseline bot plays', () {
      final rig = Rig(onRequest: (b, r) => b.sink(AiResponse.failed(r.id)));
      rig.untilAsked();
      expect(
        rig.until(() => rig.game.phase == GamePhase.moving, maxFrames: 100),
        isTrue,
      );
      expect(rig.driver.lastFallback, AiFallback.crashed);
      rig.game.dispose();
    });

    test('an answer outside the legal list: the baseline bot plays', () {
      final rig = Rig(onRequest: (b, r) => b.sink(AiResponse(r.id, 999)));
      rig.untilAsked();
      expect(
        rig.until(() => rig.game.phase == GamePhase.moving, maxFrames: 100),
        isTrue,
      );
      expect(rig.driver.lastFallback, AiFallback.invalid);
      rig.game.dispose();
    });

    for (final banked in [false, true]) {
      test(
          'a worker that never answers cannot freeze a whole game '
          '(banked $banked)', () {
        final rig = Rig(
          players: 3,
          reduced: true,
          rules: RulesConfig(bankedRolls: banked),
          onRequest: (b, r) {},
        );
        expect(
          rig.until(() => rig.game.phase == GamePhase.gameOver,
              maxFrames: 2000000),
          isTrue,
        );
        expect(rig.driver.fallbackCount, greaterThan(0));
        rig.game.dispose();
      });
    }
  });

  group('stale answers', () {
    test('a new game drops the answer of the old one', () {
      late AiRequest pending;
      late ScriptedBackend source;
      final rig = Rig(
        onRequest: (b, r) {
          pending = r;
          source = b;
        },
      );
      rig.untilAsked();
      rig.game.newGame(seed: 3);
      source.sink(AiResponse(pending.id, 0));
      for (var i = 0; i < 20; i++) {
        rig.step();
      }
      // Nothing from the old game was played in the new one.
      expect(rig.game.state.turnNumber, 0);
      expect(rig.game.phase, isNot(GamePhase.moving));
      rig.game.dispose();
    });

    test('an answer that arrives after the screen closed is harmless', () {
      late AiRequest pending;
      late ScriptedBackend source;
      final rig = Rig(
        onRequest: (b, r) {
          pending = r;
          source = b;
        },
      );
      rig.untilAsked();
      rig.game.dispose();
      expect(source.closed, isTrue);
      source.sink(AiResponse(pending.id, 0));
    });
  });
}
