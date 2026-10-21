import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/bank_tray.dart';
import 'package:ludo/ui/core/motion_spec.dart';

import 'package:ludo_app/game/game_controller.dart';

/// Seeds found with the engine (first banked sequence of seat 0):
/// 6 then 1..5 / 6, 6, 6 / a first roll of 1..5 / a game that, played with
/// "first legal move", ends a bonus sequence in a dead end with moves to undo.
const _sixThenLow = 6;
const _tripleSix = 528;
const _firstLow = 0;
const _deadEndWithMoves = 1;

const _banked = RulesConfig(bankedRolls: true);

class _Rig {
  _Rig(int seed, {RulesConfig rules = _banked}) {
    game = GameController(
      seed: seed,
      rules: rules,
      now: () => t,
      haptics: false,
    );
  }

  double t = 0;
  late final GameController game;

  /// Advances the clock by [ms] and ticks once.
  void step([double ms = 1000]) {
    t += ms;
    game.tick();
  }

  /// Rolls and lets the die settle.
  void rollSettled() {
    game.roll();
    step();
  }

  /// "First legal move" (the policy the seeds above were found with).
  void act() {
    final g = game;
    if (g.phase == GamePhase.awaitingRoll) {
      g.roll();
    } else if (g.phase == GamePhase.awaitingMove) {
      if (g.banked) {
        final c = g.choice!;
        final m = c.legal.first;
        if (c.selected != m.dieIndex) {
          g.chipTap(g.state.currentSeat, m.dieIndex);
        }
        g.tapAt(g.resting[m.owner][m.tokenIndex]);
      } else {
        final m = g.legal.first;
        g.tapAt(g.resting[m.owner][m.tokenIndex]);
      }
    }
  }
}

void main() {
  group('rule off', () {
    test('nothing of the bank UI exists in a normal game', () {
      final rig = _Rig(11, rules: const RulesConfig());
      final g = rig.game;
      expect(g.banked, isFalse);
      for (var i = 0; i < 300 && g.phase != GamePhase.gameOver; i++) {
        rig.act();
        rig.step();
        expect(g.tray.isEmpty, isTrue);
        expect(g.choice, isNull);
        expect(g.revert, isNull);
        expect(g.trayTappable(g.state.currentSeat), isFalse);
        if (g.phase == GamePhase.awaitingMove) {
          expect(identical(g.glowMoves, g.legal), isTrue);
        }
      }
      expect(g.state.turnNumber, greaterThan(0));
    });

    test('setBankedRolls switches the mode and starts a new game', () {
      final rig = _Rig(3, rules: const RulesConfig());
      final g = rig.game;
      expect(g.banked, isFalse);
      g.setBankedRolls(true);
      expect(g.banked, isTrue);
      expect(g.state.rules.bankedRolls, isTrue);
      final same = g.state;
      g.setBankedRolls(true);
      expect(identical(g.state, same), isTrue);
      g.setBankedRolls(false);
      expect(g.banked, isFalse);
    });
  });

  group('banked rolls', () {
    test('a 6 becomes a chip and the same seat rolls again', () {
      final rig = _Rig(_sixThenLow);
      final g = rig.game;
      rig.rollSettled();
      expect(g.lastRoll, 6);
      expect(g.phase, GamePhase.awaitingRoll);
      expect(g.activeSeat, 0);
      expect(g.state.bank, [6]);
      expect(g.tray.valuesOf(0), [6]);
      expect(g.trayTappable(0), isFalse);
    });

    test('the tray always mirrors the bank (a long game, all rules paths)', () {
      final rig = _Rig(_deadEndWithMoves);
      final g = rig.game;
      for (var i = 0; i < 600 && g.phase != GamePhase.gameOver; i++) {
        rig.act();
        rig.step();
        if (g.phase == GamePhase.awaitingRoll ||
            g.phase == GamePhase.awaitingMove) {
          expect(g.tray.valuesOf(g.state.currentSeat), g.state.bank,
              reason: 'step $i');
          for (var s = 0; s < 4; s++) {
            if (s != g.state.currentSeat) {
              expect(g.tray.valuesOf(s), isEmpty, reason: 'seat $s step $i');
            }
          }
        }
        if (g.phase == GamePhase.awaitingMove) {
          expect(g.choice, isNotNull);
          expect(g.glowMoves, isNotEmpty);
        } else {
          expect(g.choice, isNull);
        }
      }
      expect(g.state.turnNumber, greaterThan(0));
    });

    group('spending a bank of 6 then 1-5', () {
      late _Rig rig;
      late GameController g;
      setUp(() {
        rig = _Rig(_sixThenLow);
        g = rig.game;
        rig.rollSettled();
        rig.rollSettled();
      });

      test('the sequence ends: chips match the bank, the 6 is selected', () {
        expect(g.phase, GamePhase.awaitingMove);
        expect(g.state.bank, hasLength(2));
        expect(g.state.bank.first, 6);
        expect(g.state.bank.last, inInclusiveRange(1, 5));
        expect(g.tray.valuesOf(0), g.state.bank);
        // Only the 6 can be spent first (the low die cannot leave the yard):
        // it is selected on its own and all four yard tokens glow.
        expect(g.choice!.selected, 0);
        expect(g.tray.selectedIndex(0), 0);
        expect(g.glowMoves, hasLength(4));
        expect(g.trayTappable(0), isTrue);
        expect(g.trayTappable(1), isFalse);
      });

      test('a tap on the live die shakes it; the bank stays', () {
        rig.t += 10;
        g.dockTap(0);
        expect(g.phase, GamePhase.awaitingMove);
        expect(g.bankShakeMs, rig.t);
        expect(g.tray.shakeOffset(0, rig.t + 30, g.spec), isNot(0));
      });

      test('a chip that cannot be spent yet shakes and keeps the selection',
          () {
        rig.t += 10;
        g.chipTap(0, 1);
        expect(g.choice!.selected, 0);
        expect(g.tray.shakeOffset(0, rig.t + 30, g.spec), isNot(0));
        // Chips of other seats are not tappable.
        g.chipTap(1, 0);
        expect(g.choice!.selected, 0);
      });

      test('spend the 6, then the forced low die, then the turn passes', () {
        final low = g.state.bank.last;
        expect(g.tapAt(g.resting[0][0]), isTrue);
        expect(g.phase, GamePhase.moving);
        expect(g.choice, isNull);
        expect(g.tray.valuesOf(0), [low]);
        final flying = g.tray.chips.where((c) => c.leaving).toList();
        expect(flying, hasLength(1));
        expect(flying.single.exit, ChipExit.spend);
        expect(flying.single.value, 6);
        expect(flying.single.target, isNotNull);

        rig.step(2000);
        expect(g.phase, GamePhase.awaitingMove);
        expect(g.state.bank, [low]);
        expect(g.state.tokens[0][0], 0);
        // One legal move: it waits a moment so the chip is seen first.
        expect(g.choice!.forced, isNotNull);
        rig.step(10);
        expect(g.phase, GamePhase.awaitingMove);
        rig.step(g.spec.tray.autoSpendMs);
        expect(g.phase, GamePhase.moving);

        rig.step(2000);
        expect(g.phase, GamePhase.awaitingRoll);
        expect(g.state.bank, isEmpty);
        expect(g.activeSeat, 1);
        expect(g.tray.valuesOf(0), isEmpty);
        expect(g.state.tokens[0][0], low);

        // The spent chips are pruned once their flight is over.
        rig.step(2000);
        expect(g.tray.isEmpty, isTrue);
      });
    });

    test('three sixes wipe the whole bank and pass the turn', () {
      final rig = _Rig(_tripleSix);
      final g = rig.game;
      rig.rollSettled();
      rig.rollSettled();
      expect(g.tray.valuesOf(0), [6, 6]);
      rig.rollSettled();
      expect(g.message, 'Three sixes');
      expect(g.toasts[0]!.text, 'Three sixes');
      expect(g.phase, GamePhase.awaitingRoll);
      expect(g.activeSeat, 1);
      expect(g.state.bank, isEmpty);
      expect(g.tray.valuesOf(0), isEmpty);
      final bursting = g.tray.chips.where((c) => c.exit == ChipExit.wipe);
      expect(bursting, hasLength(2));
      rig.step(3000);
      expect(g.tray.isEmpty, isTrue);
    });

    test('a dead end with nothing moved just passes the turn', () {
      final rig = _Rig(_firstLow);
      final g = rig.game;
      rig.rollSettled();
      expect(g.lastRoll, isNot(6));
      expect(g.message, 'Turn undone');
      expect(g.toasts[0]!.text, 'Turn undone');
      expect(g.revert, isNull);
      expect(g.phase, GamePhase.awaitingRoll);
      expect(g.activeSeat, 1);
      expect(g.state.bank, isEmpty);
      // The last die is still seen for a moment, then the chips go.
      expect(g.tray.valuesOf(0), isEmpty);
      expect(g.tray.chips.where((c) => c.exit == ChipExit.revert), isNotEmpty);
      rig.step(3000);
      expect(g.tray.isEmpty, isTrue);
    });

    test('a dead end after moves glides the tokens back before the pass', () {
      final rig = _Rig(_deadEndWithMoves);
      final g = rig.game;
      for (var i = 0; i < 1500 && g.revert == null; i++) {
        rig.act();
        rig.step();
      }
      final revert = g.revert;
      expect(revert, isNotNull, reason: 'the seed no longer dead-ends');
      expect(revert!.isEmpty, isFalse);
      expect(g.phase, GamePhase.moving);
      expect(g.message, 'Turn undone');
      expect(g.state.bank, isEmpty);
      // Dust where each token lands again.
      expect(g.fx.rings, isNotEmpty);
      final roller = g.rollerSeat;
      expect(g.activeSeat, roller, reason: 'the pass waits for the glide');

      // Taps do nothing while the board glides.
      expect(g.tapAt(g.resting[roller][0]), isFalse);

      rig.t = g.revertStartMs + revert.totalMs;
      g.tick();
      expect(g.revert, isNull);
      expect(g.phase, GamePhase.awaitingRoll);
      expect(g.activeSeat, g.state.currentSeat);
      expect(g.activeSeat, isNot(roller));
    });

    test('reduced motion: no hold before the revert, chips fade in place', () {
      final rig = _Rig(_deadEndWithMoves);
      final g = rig.game;
      g.spec = MotionSpec.reduced;
      for (var i = 0; i < 1500 && g.revert == null; i++) {
        rig.act();
        rig.step();
      }
      expect(g.revert, isNotNull);
      expect(g.revertStartMs, lessThanOrEqualTo(rig.t));
    });

    test('a new game clears the tray and any revert', () {
      final rig = _Rig(_sixThenLow);
      final g = rig.game;
      rig.rollSettled();
      expect(g.tray.isEmpty, isFalse);
      g.newGame(seed: 5);
      expect(g.tray.isEmpty, isTrue);
      expect(g.choice, isNull);
      expect(g.revert, isNull);
      expect(g.bankShakeMs, lessThan(-1e8));
    });
  });
}
