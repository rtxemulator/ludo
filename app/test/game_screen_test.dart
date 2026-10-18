import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo_app/game/game_controller.dart';
import 'package:ludo_app/settings/game_settings.dart';
import 'package:ludo_app/ui/dev/frame_timing_overlay.dart';
import 'package:ludo_app/ui/board/board_view.dart';
import 'package:ludo_app/ui/dice/dock_layer.dart';
import 'package:ludo_app/ui/screens/game_screen.dart';

// The turn ticker never lets the tree settle, so tests advance time by hand.
void main() {
  testWidgets('screen shows board and docks and survives a few turns',
      (tester) async {
    var t = 0.0;
    final game = GameController(seed: 42, now: () => t, haptics: false);
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: game)));

    expect(find.byType(BoardView), findsOneWidget);
    expect(find.byType(DockLayer), findsOneWidget);
    for (var seat = 0; seat < 4; seat++) {
      expect(find.byKey(ValueKey('dock-$seat')), findsOneWidget);
    }
    // No status text anywhere.
    expect(find.byType(Text), findsNothing);

    for (var turn = 0; turn < 12; turn++) {
      if (game.phase == GamePhase.awaitingRoll) {
        await tester.tap(find.byKey(ValueKey('dock-${game.activeSeat}')));
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

  testWidgets('menu opens, shows its entries and settings change the model',
      (tester) async {
    final game = GameController(seed: 3, haptics: false);
    final settings = GameSettings(haptics: false);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: game, settings: settings)),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('New game'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Rules'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('UI orientation'), findsOneWidget);

    await tester.tap(find.text('Fixed'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(settings.orientation, UiOrientation.fixed);

    await tester.tap(find.text('On'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(settings.reduceMotion, ReduceMotion.on);
    expect(game.spec.reducedMotion, isTrue);

    expect(settings.haptics, isFalse);
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(settings.haptics, isTrue);
    expect(game.feedback.enabled, isTrue);
    game.feedback.enabled = false;

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('New game'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('frame timing overlay only exists while the setting is on',
      (tester) async {
    final game = GameController(seed: 3, haptics: false);
    final settings = GameSettings(haptics: false);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(controller: game, settings: settings)),
    );
    expect(find.byType(FrameTimingOverlay), findsNothing);
    settings.frameOverlay = true;
    await tester.pump();
    expect(find.byType(FrameTimingOverlay), findsOneWidget);
    expect(find.textContaining('fps'), findsOneWidget);
    settings.frameOverlay = false;
    await tester.pump();
    expect(find.byType(FrameTimingOverlay), findsNothing);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('game over shows the rematch card and a new game starts again',
      (tester) async {
    var t = 0.0;
    final game = GameController(
      rules: const RulesConfig(endMode: EndMode.firstToWin),
      seed: 2024,
      now: () => t,
      haptics: false,
    );
    var guard = 0;
    while (game.phase != GamePhase.gameOver && guard++ < 200000) {
      switch (game.phase) {
        case GamePhase.awaitingRoll:
          game.roll();
        case GamePhase.awaitingMove:
          final move = game.legal.first;
          game.tapAt(game.resting[move.owner][move.tokenIndex]);
        default:
          t += 1000;
          game.tick();
      }
    }
    expect(game.phase, GamePhase.gameOver);

    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: game)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Rematch'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Rematch'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.phase, GamePhase.awaitingRoll);
    expect(find.text('Rematch'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
