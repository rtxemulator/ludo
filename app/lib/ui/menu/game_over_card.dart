import 'package:flutter/material.dart';
import 'package:ludo/ui/core/table_layout.dart';

import '../../game/game_controller.dart';
import '../../settings/game_settings.dart';
import 'turned_box.dart';

/// Shared "Rematch" / "Menu" buttons at game over, facing the winner (UI/UX
/// doc sections 3 and 8). Sits in the middle of the board; the per-seat rank
/// badges are painted at the docks by the overlay painter.
class GameOverCard extends StatelessWidget {
  const GameOverCard({
    super.key,
    required this.game,
    required this.settings,
    required this.layout,
    required this.onMenu,
    this.onReplay,
  });

  final GameController game;
  final GameSettings settings;
  final TableLayout layout;
  final VoidCallback onMenu;

  /// "Watch replay" of the game just played; `null` hides the button.
  final VoidCallback? onReplay;

  /// Side of the square the card turns inside (pixels).
  static double sideFor(TableLayout layout) =>
      (layout.board.width * 0.6).clamp(190.0, 250.0);

  @override
  Widget build(BuildContext context) {
    final winner = game.winnerSeat ?? 0;
    final turns = sharedUiTurns(
      layout,
      winner,
      settings.orientation,
      autoRotate: settings.autoRotateShared,
    );
    final side = sideFor(layout);
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: game.spec.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: TurnedBox(
        turns: turns,
        side: side,
        animate: false,
        child: Center(
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            color: scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: game.rematch,
                    child: const Text('Rematch'),
                  ),
                  const SizedBox(height: 8),
                  if (onReplay != null) ...[
                    OutlinedButton(
                      key: const ValueKey('watch-replay'),
                      onPressed: onReplay,
                      child: const Text('Watch replay'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton(
                    onPressed: onMenu,
                    child: const Text('Menu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
