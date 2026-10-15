import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/pt.dart';

import 'package:ludo_app/game/game_controller.dart';

void main() {
  test('rolling reveals the result only after the dice animation', () {
    var t = 0.0;
    final game = GameController(seed: 7, now: () => t, haptics: false);
    expect(game.phase, GamePhase.awaitingRoll);

    game.roll();
    expect(game.phase, GamePhase.rolling);
    expect(game.lastRoll, isNull);

    t = 300;
    game.tick();
    expect(game.phase, GamePhase.rolling);
    expect(game.lastRoll, isNull);

    t = 700;
    game.tick();
    expect(game.phase, isNot(GamePhase.rolling));
    expect(game.lastRoll, inInclusiveRange(1, 6));
  });

  test('roll is ignored while a roll or move is in progress', () {
    var t = 0.0;
    final game = GameController(seed: 3, now: () => t, haptics: false);
    game.roll();
    final before = game.diceStartMs;
    t = 50;
    game.roll();
    expect(game.diceStartMs, before);
  });

  test('taps away from a legal token are ignored', () {
    var t = 0.0;
    final game = GameController(seed: 11, now: () => t, haptics: false);
    // Roll until a choice between several moves is needed (or give up).
    for (var i = 0; i < 500 && game.phase != GamePhase.awaitingMove; i++) {
      if (game.phase == GamePhase.awaitingRoll) {
        game.roll();
      }
      t += 1000;
      game.tick();
    }
    if (game.phase == GamePhase.awaitingMove) {
      expect(game.tapAt(const Pt(7.5, 7.5)), isFalse);
      expect(game.phase, GamePhase.awaitingMove);
    }
  });

  test('a bot can play a full first-to-win game to the end', () {
    var t = 0.0;
    final game = GameController(
      rules: const RulesConfig(endMode: EndMode.firstToWin),
      seed: 2024,
      now: () => t,
      haptics: false,
    );
    var iterations = 0;
    while (game.phase != GamePhase.gameOver && iterations++ < 200000) {
      switch (game.phase) {
        case GamePhase.awaitingRoll:
          game.roll();
        case GamePhase.awaitingMove:
          final move = game.legal.first;
          expect(game.tapAt(game.resting[move.owner][move.tokenIndex]), isTrue);
        case GamePhase.rolling:
        case GamePhase.moving:
          t += 1000;
          game.tick();
        case GamePhase.gameOver:
          break;
      }
      for (final seat in game.state.tokens) {
        expect(seat.length, 4);
      }
    }
    expect(game.phase, GamePhase.gameOver);
    expect(game.state.isOver, isTrue);
    expect(game.statusText, contains('win'));
    expect(game.needsTicker, isFalse);
  });

  test('newGame resets everything', () {
    var t = 0.0;
    final game = GameController(seed: 5, now: () => t, haptics: false);
    game.roll();
    t = 1000;
    game.tick();
    game.newGame(seed: 5);
    expect(game.phase, GamePhase.awaitingRoll);
    expect(game.lastRoll, isNull);
    expect(game.plan, isNull);
    expect(game.state.turnNumber, 0);
  });
}
