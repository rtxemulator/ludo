import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class _Setup {
  const _Setup(this.name, this.rules, this.seats);

  final String name;
  final RulesConfig rules;
  final List<int> seats;
}

List<_Setup> _setups() {
  const presets = {
    'classic': RulesConfig.classic(),
    'quick': RulesConfig.quick(),
    'strategic': RulesConfig.strategic(),
  };
  final layouts = <String, (List<int>, RulesConfig Function(RulesConfig))>{
    '2p': (const [0, 2], (r) => r),
    '3p': (const [0, 1, 2], (r) => r),
    '4p': (allSeats, (r) => r),
    '2v2 control': (allSeats, (r) => r.copyWith(teamsEnabled: true)),
    '2v2 no control': (
      allSeats,
      (r) => r.copyWith(teamsEnabled: true, teammateControl: false),
    ),
  };
  return [
    for (final preset in presets.entries)
      for (final endMode in EndMode.values)
        for (final layout in layouts.entries)
          _Setup(
            '${preset.key}/${endMode.name}/${layout.key}',
            layout.value.$2(preset.value.copyWith(endMode: endMode)),
            layout.value.$1,
          ),
  ];
}

/// Throws if [state] breaks an engine invariant.
void _checkInvariants(GameState state, String context) {
  void fail(String message) => throw StateError('$context: $message\n$state');

  if (state.tokens.length != 4) {
    fail('expected 4 seats');
  }
  for (var seat = 0; seat < 4; seat++) {
    final tokens = state.tokens[seat];
    if (tokens.length != tokensPerSeat) {
      fail('seat $seat has ${tokens.length} tokens');
    }
    for (final p in tokens) {
      if (p < yardPosition || p > finishPosition) {
        fail('seat $seat has a token at $p');
      }
      if (!state.isActive(seat) && p != yardPosition) {
        fail('inactive seat $seat moved');
      }
    }
  }

  // Opposing units never share a non-safe track square.
  final unitsOnSquare = <int, Set<int>>{};
  for (final seat in state.activeSeats) {
    for (final p in state.tokens[seat]) {
      if (isOnTrack(p)) {
        unitsOnSquare
            .putIfAbsent(absoluteSquare(seat, p), () => {})
            .add(state.unitOf(seat));
      }
    }
  }
  unitsOnSquare.forEach((square, units) {
    if (units.length > 1 && !isSafeSquare(square)) {
      fail('opponents share non-safe square $square');
    }
  });

  // Finish bookkeeping.
  if (state.finishOrder.toSet().length != state.finishOrder.length) {
    fail('duplicate in finishOrder');
  }
  for (final seat in state.finishOrder) {
    if (!state.isActive(seat)) {
      fail('inactive seat $seat in finishOrder');
    }
  }
  for (final seat in state.activeSeats) {
    if (state.seatFinished(seat) && !state.finishOrder.contains(seat)) {
      fail('seat $seat finished but is not in finishOrder');
    }
  }

  // Banked-dice bookkeeping.
  if (state.rules.bankedRolls) {
    if (state.dice != null) {
      fail('banked rules must never set a pending die');
    }
    if (state.bankPhase == BankPhase.moving && state.turnSnapshot == null) {
      fail('moving phase without a snapshot');
    }
    if (state.bank.any((d) => d < 1 || d > 6)) {
      fail('bank holds a non-die value');
    }
    if (state.bank.isNotEmpty &&
        state.bankPhase == BankPhase.rolling &&
        state.turnSnapshot == null &&
        state.bank.any((d) => d != 6)) {
      fail('a non-6 in the bank before the moving phase');
    }
  } else if (state.bank.isNotEmpty || state.turnSnapshot != null) {
    fail('bank state without bankedRolls');
  }

  if (state.isOver) {
    if (state.dice != null || state.bank.isNotEmpty) {
      fail('dice pending after the game ended');
    }
    if (state.rules.endMode == EndMode.fullRanking &&
        state.finishOrder.length != state.activeSeats.length) {
      fail('fullRanking ended without a complete finishOrder');
    }
    if (state.winners == null) {
      fail('game over without a winner');
    }
  } else if (!state.isSeatInPlay(state.currentSeat)) {
    fail('turn belongs to a seat that is out of play');
  }
}

void main() {
  final setups = _setups();

  test(
    '10,000 random playouts never break an engine invariant',
    () {
      const games = 10000;
      var totalSteps = 0;
      for (var game = 0; game < games; game++) {
        final setup = setups[game % setups.length];
        final seed = 1000 + game;
        final context = 'game $game (${setup.name}, seed $seed)';

        final result = playOut(
          seed: seed,
          chooser: Random(game),
          rules: setup.rules,
          activeSeats: setup.seats,
          onState: (s) => _checkInvariants(s, context),
        );
        totalSteps += result.steps;

        // 2. Terminates cleanly within a reasonable turn limit.
        expect(result.finished, isTrue, reason: '$context did not finish');
        expect(result.state.isOver, isTrue, reason: context);

        // Replays reproduce the game exactly (sampled to bound runtime).
        if (game % 25 == 0) {
          final replayed = Engine.replay(
            seed: seed,
            log: result.log,
            rules: setup.rules,
            activeSeats: setup.seats,
          );
          expect(replayed, result.state, reason: '$context replay');
        }
      }
      expect(totalSteps, greaterThan(games));
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );

  test('banked-dice playouts never break an engine invariant', () {
    final banked = [
      for (final setup in setups)
        if (setup.name.startsWith('classic/') ||
            setup.name.startsWith('strategic/'))
          _Setup(
            'banked ${setup.name}',
            setup.rules.copyWith(bankedRolls: true),
            setup.seats,
          ),
    ];
    const games = 600;
    for (var game = 0; game < games; game++) {
      final setup = banked[game % banked.length];
      final seed = 5000 + game;
      final context = 'game $game (${setup.name}, seed $seed)';
      final result = playOut(
        seed: seed,
        chooser: Random(game),
        rules: setup.rules,
        activeSeats: setup.seats,
        onState: (s) => _checkInvariants(s, context),
      );
      expect(result.finished, isTrue, reason: '$context did not finish');
      if (game % 10 == 0) {
        final replayed = Engine.replay(
          seed: seed,
          log: result.log,
          rules: setup.rules,
          activeSeats: setup.seats,
        );
        expect(replayed, result.state, reason: '$context replay');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('every setup is exercised and covers all end modes', () {
    expect(setups, hasLength(30));
    expect(setups.map((s) => s.rules.endMode).toSet(), EndMode.values.toSet());
    expect(setups.where((s) => s.rules.teamsEnabled), isNotEmpty);
    expect(setups.where((s) => s.rules.blockades), isNotEmpty);
  });

  test('total token count per seat is always 4 (copy-on-write check)', () {
    final result = playOut(seed: 77, chooser: Random(77));
    for (final seat in result.state.tokens) {
      expect(seat, hasLength(4));
    }
  });
}
