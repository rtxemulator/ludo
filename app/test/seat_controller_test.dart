import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';

import 'package:ludo_app/game/game_controller.dart';

/// Advances the fake clock in 100 ms frames until [done] or [maxFrames].
void run(
  GameController game,
  void Function(double) setClock, {
  required bool Function() done,
  int maxFrames = 200000,
  void Function()? onFrame,
}) {
  var t = 0.0;
  for (var frame = 0; frame < maxFrames && !done(); frame++) {
    t += 100;
    setClock(t);
    onFrame?.call();
    game.tick();
  }
}

void main() {
  MatchSetup bots(int players, {RulesConfig rules = const RulesConfig()}) {
    var setup = MatchSetup.hotSeat(players: players, rules: rules);
    for (final seat in setup.activeSeats) {
      setup = setup.withSeat(seat, const SeatConfig.ai());
    }
    return setup;
  }

  test('a two-player setup only seats the opposite corners', () {
    final game = GameController(
      setup: MatchSetup.hotSeat(players: 2),
      seed: 1,
      haptics: false,
    );
    expect(game.state.activeSeats, [0, 2]);
    expect(game.setup.playerCount, 2);
    expect(game.activeSeat, 0);
  });

  test('the default controller is still four hot-seat humans', () {
    final game = GameController(seed: 1, haptics: false);
    expect(game.state.activeSeats, [0, 1, 2, 3]);
    expect(game.aiTurn, isFalse);
  });

  test('banked rolls keep the seats', () {
    final game = GameController(
      setup: MatchSetup.hotSeat(players: 3),
      seed: 1,
      haptics: false,
    );
    game.setBankedRolls(true);
    expect(game.banked, isTrue);
    expect(game.state.activeSeats, [0, 1, 2]);
    expect(game.rules.bankedRolls, isTrue);
  });

  test('taps do nothing on the computer\'s turn', () {
    var t = 0.0;
    final setup =
        MatchSetup.hotSeat(players: 3).withSeat(0, const SeatConfig.ai());
    final game = GameController(
      setup: setup,
      seed: 3,
      now: () => t,
      haptics: false,
    );
    expect(game.aiTurn, isTrue);

    t = 50;
    game.dockTap(0);
    expect(game.phase, GamePhase.awaitingRoll);
    expect(game.dockPulseMs[0], 50);
    expect(game.tapAt(const Pt(3, 3)), isFalse);
    expect(game.phase, GamePhase.awaitingRoll);
  });

  test('an AI seat rolls by itself after a think time', () {
    var t = 0.0;
    final game = GameController(
      setup: bots(2),
      seed: 5,
      now: () => t,
      haptics: false,
    );
    game.tick();
    expect(game.phase, GamePhase.awaitingRoll);

    // Not yet: the think time has not passed.
    t = 300;
    game.tick();
    expect(game.phase, GamePhase.awaitingRoll);

    t = 800;
    game.tick();
    expect(game.phase, GamePhase.rolling);
    expect(game.rollerSeat, 0);
  });

  test('two AI seats play a whole game with nobody touching the screen', () {
    var t = 0.0;
    final game = GameController(
      setup: bots(2),
      seed: 8,
      now: () => t,
      haptics: false,
    )..spec = MotionSpec.reduced;
    run(
      game,
      (v) => t = v,
      done: () => game.phase == GamePhase.gameOver,
    );
    expect(game.phase, GamePhase.gameOver);
    expect(game.state.isOver, isTrue);
    expect(game.state.winners, isNotEmpty);
  });

  test('AI seats also play banked-roll games to the end', () {
    var t = 0.0;
    final game = GameController(
      setup: bots(3, rules: const RulesConfig(bankedRolls: true)),
      seed: 21,
      now: () => t,
      haptics: false,
    )..spec = MotionSpec.reduced;
    run(
      game,
      (v) => t = v,
      done: () => game.phase == GamePhase.gameOver,
    );
    expect(game.phase, GamePhase.gameOver);
  });

  test('a human and an AI alternate; only the human needs to act', () {
    var t = 0.0;
    final setup =
        MatchSetup.hotSeat(players: 2).withSeat(2, const SeatConfig.ai());
    final game = GameController(
      setup: setup,
      seed: 14,
      now: () => t,
      haptics: false,
    )..spec = MotionSpec.reduced;
    final seen = <int>{};
    run(
      game,
      (v) => t = v,
      maxFrames: 20000,
      done: () => game.phase == GamePhase.gameOver,
      onFrame: () {
        if (game.aiTurn) {
          seen.add(game.state.currentSeat);
          return;
        }
        // The human plays like a person would: tap the dock, then a token.
        if (game.phase == GamePhase.awaitingRoll) {
          game.dockTap(game.state.currentSeat);
        } else if (game.phase == GamePhase.awaitingMove) {
          final move = game.legal.first;
          game.tapAt(game.resting[move.owner][move.tokenIndex]);
        }
      },
    );
    expect(seen, {2});
    expect(game.state.turnNumber, greaterThan(10));
    expect(
      game.phase == GamePhase.gameOver ||
          game.state.tokens[2].any((p) => p != yardPosition),
      isTrue,
    );
  });

  test('the same seed gives the same AI game', () {
    GameState play() {
      var t = 0.0;
      final game = GameController(
        setup: bots(2),
        seed: 33,
        now: () => t,
        haptics: false,
      )..spec = MotionSpec.reduced;
      run(
        game,
        (v) => t = v,
        done: () => game.phase == GamePhase.gameOver,
      );
      return game.state;
    }

    final a = play();
    final b = play();
    expect(a.tokens, b.tokens);
    expect(a.turnNumber, b.turnNumber);
  });
}
