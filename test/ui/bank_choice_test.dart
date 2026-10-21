import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/bank_choice.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

const _banked = RulesConfig(bankedRolls: true);

/// A moving-phase state for seat 0 holding [bank] with the given tokens.
GameState _moving(List<int> seat0, List<int> bank) => makeState(
      rules: _banked,
      tokens: {0: seat0},
      bank: bank,
      bankPhase: BankPhase.moving,
      turnSnapshot: TurnSnapshot(
        tokens: [
          seat0,
          List.filled(4, -1),
          List.filled(4, -1),
          List.filled(4, -1),
        ],
        finishOrder: const [],
        bank: bank,
      ),
    );

void main() {
  group('two playable values', () {
    // Tokens at 10 and 20: both can use the 3 and the 5.
    final state = _moving([10, 20, -1, -1], [3, 5]);

    test('nothing is selected and every legal token glows', () {
      final choice = BankChoice.of(state);
      expect(choice.playableValues, [3, 5]);
      expect(choice.selected, isNull);
      expect(choice.selectedValue, isNull);
      expect(choice.glowMoves, hasLength(4));
      expect(choice.forced, isNull);
    });

    test('tapping a chip selects it and the glow narrows to its value', () {
      final choice = BankChoice.of(state);
      expect(choice.tapChip(1), isTrue);
      expect(choice.selected, 1);
      expect(choice.selectedValue, 5);
      final glow = choice.glowMoves;
      expect(glow, hasLength(2));
      expect(glow.every((m) => choice.valueOf(m) == 5), isTrue);
    });

    test('tapping the selected chip again deselects it', () {
      final choice = BankChoice.of(state)..tapChip(0);
      expect(choice.tapChip(0), isTrue);
      expect(choice.selected, isNull);
      expect(choice.glowMoves, hasLength(4));
    });

    test('a chip outside the bank is refused and changes nothing', () {
      final choice = BankChoice.of(state)..tapChip(0);
      expect(choice.tapChip(7), isFalse);
      expect(choice.tapChip(-1), isFalse);
      expect(choice.selected, 0);
    });

    test('with a chip selected a token spends exactly that die', () {
      final choice = BankChoice.of(state)..tapChip(1);
      final r = choice.tapToken(0, 1);
      expect(r.kind, TokenTapKind.spend);
      expect(r.move!.tokenIndex, 1);
      expect(r.move!.dieIndex, 1);
      expect(r.move!.to, 25);
      // The engine accepts the move as given.
      final after = Engine.apply(state, r.move!);
      expect(after.tokens[0][1], 25);
      expect(after.bank, [3]);
    });

    test('a token with two playable dice and nothing selected prompts', () {
      final choice = BankChoice.of(state);
      final r = choice.tapToken(0, 0);
      expect(r.kind, TokenTapKind.prompt);
      expect(r.move, isNull);
      expect(choice.selected, isNull);
    });

    test('a token that cannot move at all is none', () {
      final choice = BankChoice.of(state);
      expect(choice.tapToken(0, 2).kind, TokenTapKind.none); // yard, no 6
      expect(choice.tapToken(1, 0).kind, TokenTapKind.none); // not on turn
    });
  });

  group('one playable value', () {
    test('it is selected automatically; equal dice are interchangeable', () {
      final state = _moving([10, 20, -1, -1], [3, 3]);
      final choice = BankChoice.of(state);
      expect(choice.playableValues, [3]);
      expect(choice.selected, 0);
      // One legal move per token (equal dice are one option).
      expect(choice.legal, hasLength(2));
      expect(choice.glowMoves, hasLength(2));
      // Tapping the only chip keeps it selected.
      expect(choice.tapChip(0), isTrue);
      expect(choice.selected, 0);
      final r = choice.tapToken(0, 0);
      expect(r.kind, TokenTapKind.spend);
      expect(r.move!.dieIndex, 0);
    });

    test('a single die and a single token is a forced move', () {
      final state = _moving([10, -1, -1, -1], [3]);
      final choice = BankChoice.of(state);
      expect(choice.forced, isNotNull);
      expect(choice.forced!.to, 13);
      expect(choice.selected, 0);
    });

    test('a token with a single option spends it without a selection', () {
      // The token at 54 can only use the 2 (the finish is 2 away); the
      // token at 10 can use either die.
      final state = _moving([10, 54, -1, -1], [2, 5]);
      final choice = BankChoice.of(state);
      expect(choice.playableValues, [2, 5]);
      expect(choice.selected, isNull);
      final r = choice.tapToken(0, 1);
      expect(r.kind, TokenTapKind.spend);
      expect(r.move!.dieIndex, 0);
      expect(r.move!.to, 56);
    });

    test('a token that cannot use the selected die moves the selection', () {
      final state = _moving([10, 54, -1, -1], [2, 5]);
      final choice = BankChoice.of(state)..tapChip(1); // the 5
      expect(choice.glowMoves.map((m) => m.tokenIndex).toSet(), {0});
      final r = choice.tapToken(0, 1);
      expect(r.kind, TokenTapKind.select);
      expect(r.chip, 0);
      expect(r.move, isNull);
      expect(choice.selected, 0);
      expect(choice.glowMoves.map((m) => m.tokenIndex).toSet(), {0, 1});
    });
  });
}
