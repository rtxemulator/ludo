import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_app/game/game_controller.dart';
import 'package:ludo_app/ui/board/board_view.dart';
import 'package:ludo_app/ui/dice/dice_view.dart';
import 'package:ludo_app/ui/screens/game_screen.dart';

void main() {
  testWidgets('screen shows board and dice and survives a few turns',
      (tester) async {
    var t = 0.0;
    final game = GameController(seed: 42, now: () => t, haptics: false);
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: game)));

    expect(find.byType(BoardView), findsOneWidget);
    expect(find.byType(DiceView), findsOneWidget);
    expect(find.textContaining('tap the dice'), findsOneWidget);

    for (var turn = 0; turn < 12; turn++) {
      if (game.phase == GamePhase.awaitingRoll) {
        await tester.tap(find.byType(DiceView));
      } else if (game.phase == GamePhase.awaitingMove) {
        final move = game.legal.first;
        final p = game.resting[move.owner][move.tokenIndex];
        final box = tester.getRect(find.byType(BoardView));
        final cell = box.width / 15;
        await tester.tapAt(box.topLeft + Offset(p.x * cell, p.y * cell));
      }
      for (var frame = 0; frame < 4; frame++) {
        t += 400;
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    expect(tester.takeException(), isNull);

    // Disposes the ticker cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion is picked up from MediaQuery', (tester) async {
    final game = GameController(seed: 1, haptics: false);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: GameScreen(controller: game),
        ),
      ),
    );
    expect(game.spec.reducedMotion, isTrue);
    await tester.pumpWidget(const SizedBox());
    game.dispose();
  });
}
