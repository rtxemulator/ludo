/// Choosing what to spend in a banked-rolls moving phase: which chip is
/// selected, which tokens glow, what a tap on a token or a chip means.
/// Pure Dart; the controller only forwards taps and draws the answer.
/// Spec: docs/ludo-ui-ux.md section 10.
library;

import 'package:ludo/engine/ludo_engine.dart';

/// What a tap on a token means.
enum TokenTapKind {
  /// The token cannot move at all.
  none,

  /// Spend [TokenTapResult.move] on it.
  spend,

  /// The token cannot use the selected die but can use another one: the
  /// selection moves to that chip ([TokenTapResult.chip]), nothing is spent.
  select,

  /// The token could use several dice and none is selected (or the selected
  /// one does not fit): the tray prompts the player to pick a die.
  prompt,

  /// The token has several ways to spend the die (alone, or together with
  /// its blockade partner): [TokenTapResult.moves] to choose from.
  variants,
}

class TokenTapResult {
  const TokenTapResult(this.kind, {this.move, this.chip, this.moves});

  final TokenTapKind kind;
  final Move? move;
  final int? chip;
  final List<Move>? moves;
}

/// The spend decision of one moving phase.
///
/// Built from the state when the moving phase (or the next spend of it)
/// begins; [selected] is an index into [bank].
class BankChoice {
  BankChoice._(this.bank, this.legal, this.selected);

  /// Choice for [state], which must be in the banked moving phase.
  factory BankChoice.of(GameState state) {
    final bank = List<int>.unmodifiable(state.bank);
    final legal = List<Move>.unmodifiable(Engine.legalMoves(state));
    final choice = BankChoice._(bank, legal, null);
    final values = choice.playableValues;
    if (values.length == 1) {
      choice.selected = bank.indexOf(values.first);
    }
    return choice;
  }

  /// The dice in rolled order.
  final List<int> bank;

  /// `Engine.legalMoves(state)`: one move per token and distinct value.
  final List<Move> legal;

  /// Selected chip (index into [bank]), or `null`. Selected automatically
  /// when only one value can be played.
  int? selected;

  /// Value of the die [move] spends.
  int valueOf(Move move) => bank[move.dieIndex];

  /// Distinct values that have at least one legal move, in bank order.
  List<int> get playableValues {
    final values = <int>[];
    for (final move in legal) {
      final v = valueOf(move);
      if (!values.contains(v)) {
        values.add(v);
      }
    }
    values.sort((a, b) => bank.indexOf(a).compareTo(bank.indexOf(b)));
    return values;
  }

  /// Whether chip [index] can be spent now.
  bool isPlayable(int index) =>
      index >= 0 &&
      index < bank.length &&
      legal.any((m) => valueOf(m) == bank[index]);

  /// The value of the selected chip.
  int? get selectedValue => selected == null ? null : bank[selected!];

  /// The only legal move, when there is exactly one (a forced spend).
  Move? get forced => legal.length == 1 ? legal.first : null;

  /// Moves whose tokens glow: those of the selected value, or every legal
  /// move while nothing is selected.
  List<Move> get glowMoves {
    final value = selectedValue;
    if (value == null) {
      return legal;
    }
    return [
      for (final m in legal)
        if (valueOf(m) == value) m,
    ];
  }

  /// Taps chip [index]. Returns `false` (and changes nothing) when it cannot
  /// be spent. Tapping the selected chip again deselects it, unless only one
  /// value is playable (then it stays selected).
  bool tapChip(int index) {
    if (!isPlayable(index)) {
      return false;
    }
    if (selected == index) {
      if (playableValues.length > 1) {
        selected = null;
      }
      return true;
    }
    selected = index;
    return true;
  }

  /// What a tap on token ([owner], [tokenIndex]) does. A [TokenTapKind.select]
  /// result is applied to [selected] here; a [TokenTapKind.spend] result is
  /// not (the controller spends it and the choice ends with the spend).
  TokenTapResult tapToken(int owner, int tokenIndex) {
    final mine = [
      for (final m in legal)
        if (m.owner == owner && m.moves(tokenIndex)) m,
    ];
    if (mine.isEmpty) {
      return const TokenTapResult(TokenTapKind.none);
    }
    final values = {for (final m in mine) valueOf(m)};
    final sel = selected;
    if (sel != null) {
      final value = bank[sel];
      final fits = [
        for (final m in mine)
          if (valueOf(m) == value) _with(m, sel),
      ];
      if (fits.length == 1) {
        return TokenTapResult(TokenTapKind.spend, move: fits.single);
      }
      if (fits.length > 1) {
        return TokenTapResult(TokenTapKind.variants, moves: fits);
      }
      if (values.length == 1) {
        final chip = bank.indexOf(values.single);
        selected = chip;
        return TokenTapResult(TokenTapKind.select, chip: chip);
      }
      return const TokenTapResult(TokenTapKind.prompt);
    }
    if (values.length == 1) {
      return mine.length == 1
          ? TokenTapResult(TokenTapKind.spend, move: mine.single)
          : TokenTapResult(TokenTapKind.variants, moves: mine);
    }
    return const TokenTapResult(TokenTapKind.prompt);
  }

  static Move _with(Move m, int dieIndex) => Move(
        owner: m.owner,
        tokenIndex: m.tokenIndex,
        from: m.from,
        to: m.to,
        dieIndex: dieIndex,
        partnerIndex: m.partnerIndex,
      );
}
