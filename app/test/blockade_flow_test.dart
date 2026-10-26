import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/ai/ai.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/pt.dart';

import 'package:ludo_app/game/game_controller.dart';

/// Moving blockades in the game flow: a tapped pair offers "just this token"
/// or "the whole blockade", and the choice is made by tapping a marker.
void main() {
  const rules = RulesConfig(
    blockades: true,
    blockadeMovement: true,
  );

  double t = 0;

  GameController table({RulesConfig r = rules, bool bank = false}) {
    t = 0;
    final game = GameController(
      setup: MatchSetup.hotSeat(players: 2, rules: r),
      seed: 1,
      now: () => t,
      haptics: false,
    )..spec = MotionSpec.reduced;
    return game;
  }

  GameState withPair(GameController game, {int? dice}) {
    final base = game.state;
    return GameState(
      tokens: [
        [10, 10, -1, -1],
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
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

  test('tapping a pair that can move alone or together offers both', () {
    final game = table();
    game.debugLoad(withPair(game, dice: 4));
    expect(game.phase, GamePhase.awaitingMove);

    expect(game.tapAt(game.resting[0][0]), isFalse);
    expect(game.variants, hasLength(2));
    expect(game.variants.where((m) => m.isUnit), hasLength(1));
    expect(game.variantPoints, hasLength(game.variants.length));
    expect(game.phase, GamePhase.awaitingMove); // nothing moved yet
  });

  test('the partner token offers the same choice', () {
    final game = table();
    game.debugLoad(withPair(game, dice: 4));
    game.tapAt(game.resting[0][1]);
    expect(game.variants.any((m) => m.isUnit), isTrue);
    expect(game.variants.any((m) => !m.isUnit && m.tokenIndex == 1), isTrue);
  });

  test('tapping the blockade marker moves both tokens', () {
    final game = table();
    game.debugLoad(withPair(game, dice: 4));
    game.tapAt(game.resting[0][0]);
    final unit = game.variants.indexWhere((m) => m.isUnit);
    expect(game.tapAt(game.variantPoints[unit]), isTrue);
    expect(game.phase, GamePhase.moving);
    expect(game.plan!.partner, isNotNull);
    settle(game);
    expect(game.state.tokens[0].take(2), [12, 12]);
    expect(game.variants, isEmpty);
  });

  test('tapping the single-token marker moves one token', () {
    final game = table();
    game.debugLoad(withPair(game, dice: 4));
    game.tapAt(game.resting[0][0]);
    final single = game.variants.indexWhere((m) => !m.isUnit);
    game.tapAt(game.variantPoints[single]);
    settle(game);
    expect(game.state.tokens[0].take(2).toSet(), {10, 14});
  });

  test('tapping elsewhere cancels the choice', () {
    final game = table();
    game.debugLoad(withPair(game, dice: 4));
    game.tapAt(game.resting[0][0]);
    expect(game.variants, isNotEmpty);
    game.tapAt(const Pt(0.2, 0.2));
    expect(game.variants, isEmpty);
    expect(game.phase, GamePhase.awaitingMove);
  });

  test('an odd roll has no unit move: a tap just moves the token', () {
    final game = table();
    game.debugLoad(withPair(game, dice: 3));
    expect(game.glowMoves.map((m) => m.tokenIndex), [0, 1]);
    expect(game.tapAt(game.resting[0][0]), isTrue);
    expect(game.phase, GamePhase.moving);
    settle(game);
    expect(game.state.tokens[0].take(2).toSet(), {10, 13});
  });

  test('both tokens of a pair glow, even when only the unit can move', () {
    final game = table(
      r: rules.copyWith(blockadeUnbreakable: true),
    );
    game.debugLoad(withPair(game, dice: 4));
    expect(game.legal.every((m) => m.isUnit), isTrue);
    expect(game.glowMoves.map((m) => m.tokenIndex).toSet(), {0, 1});
    // Only one way to move: a tap starts it.
    expect(game.tapAt(game.resting[0][1]), isTrue);
    settle(game);
    expect(game.state.tokens[0].take(2), [12, 12]);
  });

  test('banked rolls: the selected die decides, then the marker', () {
    final game = table(r: rules.copyWith(bankedRolls: true));
    final base = game.state;
    final start = GameState(
      tokens: [
        [10, 10, -1, -1],
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
      ],
      rules: base.rules,
      activeSeats: base.activeSeats,
      currentSeat: 0,
      rngState: 1,
      bank: const [4],
      bankPhase: BankPhase.moving,
      turnSnapshot: TurnSnapshot(
        tokens: const [
          [10, 10, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
        finishOrder: const [],
        bank: const [4],
      ),
    );
    game.debugLoad(start);
    game.tapAt(game.resting[0][0]);
    expect(game.variants.any((m) => m.isUnit), isTrue);
    final unit = game.variants.indexWhere((m) => m.isUnit);
    game.tapAt(game.variantPoints[unit]);
    settle(game);
    expect(game.state.tokens[0].take(2), [12, 12]);
  });

  test('two tokens on the yard exit can step out as a blockade', () {
    final game = table(r: const RulesConfig(blockades: true));
    final base = game.state;
    game.debugLoad(
      GameState(
        tokens: [
          [0, 0, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
        rules: base.rules,
        activeSeats: base.activeSeats,
        currentSeat: 0,
        dice: 4,
        rngState: 1,
      ),
    );
    game.tapAt(game.resting[0][0]);
    final unit = game.variants.indexWhere((m) => m.isUnit);
    expect(unit, isNonNegative);
    game.tapAt(game.variantPoints[unit]);
    expect(game.plan!.formed, isTrue);
    settle(game);
    expect(game.state.tokens[0].take(2), [2, 2]);
    expect(Engine.blockades(game.state), [(seat: 0, square: 2)]);
  });

  test('AI seats play whole games with every blockade option', () {
    const all = RulesConfig(
      blockades: true,
      blockadeFriendlyRestriction: true,
      blockadeMovement: true,
      blockadeCapture: true,
      blockadeUnbreakable: true,
      pieceOnBlockade: true,
    );
    for (final banked in [false, true]) {
      t = 0;
      var setup = MatchSetup.hotSeat(
          players: 3,
          rules: all.copyWith(
            bankedRolls: banked,
          ));
      for (final seat in setup.activeSeats) {
        setup = setup.withSeat(seat, const SeatConfig.ai());
      }
      final game = GameController(
        setup: setup,
        seed: 4,
        now: () => t,
        haptics: false,
        aiDriver: AiTurnDriver.inline(),
      )..spec = MotionSpec.reduced;
      for (var i = 0; i < 400000 && game.phase != GamePhase.gameOver; i++) {
        t += 100;
        game.tick();
      }
      expect(game.phase, GamePhase.gameOver, reason: 'banked $banked');
    }
  });
}
