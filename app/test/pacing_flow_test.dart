import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/pacing.dart';
import 'package:ludo/ui/core/pt.dart';

import 'package:ludo_app/game/game_controller.dart';

/// Move preview (tap to see, tap again to play), the single-move auto-play
/// setting and the pacing of a turn (the roll stays visible when there is no
/// move, a tap skips a long sequence).
void main() {
  double t = 0;

  GameController table({int seed = 1}) {
    t = 0;
    return GameController(seed: seed, now: () => t, haptics: false);
  }

  /// Seat 0 to move with [dice]; [mine] are its tokens, [others] seat 2's.
  GameState position(
    GameController game, {
    required int dice,
    List<int> mine = const [10, -1, -1, -1],
    List<int> others = const [-1, -1, -1, -1],
  }) {
    final base = game.state;
    return GameState(
      tokens: [
        mine,
        const [-1, -1, -1, -1],
        others,
        const [-1, -1, -1, -1],
      ],
      rules: base.rules,
      activeSeats: base.activeSeats,
      currentSeat: 0,
      dice: dice,
      rngState: 1,
    );
  }

  void settle(GameController game) {
    for (var i = 0; i < 400 && game.phase == GamePhase.moving; i++) {
      t += 100;
      game.tick();
    }
  }

  group('move preview', () {
    test('the first tap previews, a second tap on the token plays it', () {
      final game = table();
      game.debugLoad(position(game, dice: 3));
      final at = game.resting[0][0];

      expect(game.tapAt(at), isFalse);
      expect(game.preview, isNotNull);
      expect(game.preview!.isFor(0, 0), isTrue);
      expect(game.phase, GamePhase.awaitingMove);
      expect(game.state.tokens[0][0], 10, reason: 'nothing moved yet');

      expect(game.tapAt(at), isTrue);
      expect(game.phase, GamePhase.moving);
      expect(game.preview, isNull);
      settle(game);
      expect(game.state.tokens[0][0], 13);
    });

    test('a tap on the destination ring plays the move too', () {
      final game = table();
      game.debugLoad(position(game, dice: 3));
      game.tapAt(game.resting[0][0]);
      final ring = game.preview!.destination;
      expect(game.tapAt(ring), isTrue);
      expect(game.phase, GamePhase.moving);
    });

    test('a tap elsewhere cancels the preview and moves nothing', () {
      final game = table();
      game.debugLoad(position(game, dice: 3));
      game.tapAt(game.resting[0][0]);
      expect(game.preview, isNotNull);
      expect(game.tapAt(const Pt(7.5, 7.5)), isFalse);
      expect(game.preview, isNull);
      expect(game.phase, GamePhase.awaitingMove);
      expect(game.state.tokens[0][0], 10);
    });

    test('a move that captures previews as a capture', () {
      final game = table();
      // Seat 2's token on absolute square 12 (relative 38): a plain square.
      game.debugLoad(
        position(game, dice: 3, mine: const [
          9,
          -1,
          -1,
          -1
        ], others: const [
          38,
          -1,
          -1,
          -1,
        ]),
      );
      game.tapAt(game.resting[0][0]);
      expect(game.preview!.isCapture, isTrue);
      expect(game.preview!.captured, hasLength(1));
    });

    test('previewing never changes the game', () {
      final game = table();
      final loaded = position(game, dice: 3);
      game.debugLoad(loaded);
      game.tapAt(game.resting[0][0]);
      expect(game.state.tokens[0], [10, -1, -1, -1]);
      expect(game.moveLog, isEmpty);
    });
  });

  group('auto-move a single option', () {
    /// Rolls from a position where only the one token on the track can move
    /// (unless a 6 lets another leave the yard), until a roll offers a single
    /// move; returns whether one was found.
    bool rollSingle(GameController game) {
      for (var i = 0; i < 60; i++) {
        game.debugLoad(position(game, dice: 3).copyForRoll(i + 1));
        game.roll();
        t += 1200;
        game.tick();
        if (game.phase == GamePhase.moving ||
            (game.phase == GamePhase.awaitingMove && game.legal.length == 1)) {
          return true;
        }
        // A 6 (two moves): start over.
      }
      return false;
    }

    test('off by default: the lone move waits for a tap', () {
      final game = table();
      expect(game.autoMoveSingle, isFalse);
      expect(rollSingle(game), isTrue);
      expect(game.phase, GamePhase.awaitingMove);
      expect(game.legal, hasLength(1));
    });

    test('on: the lone move plays by itself after the die shows its face', () {
      final game = table()..autoMoveSingle = true;
      expect(rollSingle(game), isTrue);
      expect(game.phase, GamePhase.moving);
    });
  });

  group('pacing', () {
    /// A table where seat 0 has no token out: rolls of 1 to 5 have no move.
    bool rollNoMove(GameController game) {
      for (var i = 0; i < 60; i++) {
        game.debugLoad(
          position(game, dice: 3, mine: const [-1, -1, -1, -1])
              .copyForRoll(i + 1),
        );
        game.roll();
        t += 1000;
        game.tick();
        if (game.message == 'No move') {
          return true;
        }
      }
      return false;
    }

    test('with no legal move the roll stays about 600 ms, then the turn passes',
        () {
      final game = table();
      expect(rollNoMove(game), isTrue);
      // Shown, not passed yet: the roller is still the one on turn.
      final shownAt = t;
      expect(game.activeSeat, 0);
      expect(game.animating, isTrue);
      t = shownAt + 300;
      game.tick();
      expect(game.activeSeat, 0);
      // About 600 ms after the settle the turn passes.
      t = shownAt + Pacing.noMoveHoldMs + 20;
      game.tick();
      expect(game.activeSeat, game.state.currentSeat);
      expect(game.activeSeat, isNot(0));
    });

    test('a roll cannot start while the hold is still running', () {
      final game = table();
      expect(rollNoMove(game), isTrue);
      final before = game.diceStartMs;
      // A tap on the dock of the seat still on turn skips the hold...
      game.dockTap(0);
      expect(game.activeSeat, game.state.currentSeat);
      // ...and a tap during a long sequence does not start a roll.
      expect(game.phase, GamePhase.awaitingRoll);
      expect(game.diceStartMs, before);
    });

    test('a tap during the dice roll skips to the result', () {
      final game = table(seed: 9);
      game.roll();
      t = 100;
      game.tick();
      expect(game.phase, GamePhase.rolling);
      expect(game.skip(), isTrue);
      expect(game.phase, isNot(GamePhase.rolling));
      expect(game.lastRoll, isNotNull);
    });

    test('nothing to skip when the table is idle', () {
      final game = table();
      expect(game.skip(), isFalse);
      expect(game.phase, GamePhase.awaitingRoll);
    });

    test('a replay controller never skips', () {
      final game = GameController(
        seed: 1,
        now: () => t,
        haptics: false,
        replay: true,
      );
      expect(game.skip(), isFalse);
    });
  });
}

extension on GameState {
  /// The same position without a die, as a fresh roll needs.
  GameState copyForRoll(int seed) => GameState(
        tokens: [for (final seat in tokens) List<int>.of(seat)],
        rules: rules,
        activeSeats: activeSeats,
        currentSeat: currentSeat,
        rngState: seed,
      );
}
