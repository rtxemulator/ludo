import 'package:flutter/material.dart';
import 'package:ludo/seats/seats.dart';

import '../../game/replay_controller.dart';
import 'replay_text.dart';

/// The bar under the replayed table: what happened in this step, the
/// position, a scrubber, the transport buttons and the speed.
class ReplayControls extends StatelessWidget {
  const ReplayControls({super.key, required this.replay, this.notice});

  final ReplayController replay;

  /// Said above everything else when the replay is only part of the game
  /// ("Damaged save: ..."); `null` when it is whole.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final MatchSetup setup = replay.script.save.setup;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: AnimatedBuilder(
            animation: replay,
            builder: (context, _) {
              final step = replay.step;
              final turn = step == null
                  ? replay.script.at(0).turnNumber
                  : step.ready.turnNumber;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        notice!,
                        key: const ValueKey('replay-notice'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  Text(
                    step == null
                        ? 'Start of the game'
                        : describeStep(step, setup),
                    key: const ValueKey('replay-step-text'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    'Move ${replay.position} of ${replay.length} · Turn $turn',
                    key: const ValueKey('replay-position'),
                    style: theme.textTheme.bodySmall,
                  ),
                  SizedBox(
                    height: 36,
                    child: Slider(
                      key: const ValueKey('replay-slider'),
                      min: 0,
                      max: replay.length == 0 ? 1 : replay.length.toDouble(),
                      divisions: replay.length == 0 ? null : replay.length,
                      value: replay.position.toDouble(),
                      onChanged: replay.length == 0
                          ? null
                          : (v) => replay.seek(v.round()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        key: const ValueKey('replay-start'),
                        tooltip: 'Jump to start',
                        icon: const Icon(Icons.skip_previous),
                        onPressed: replay.atStart ? null : replay.toStart,
                      ),
                      IconButton(
                        key: const ValueKey('replay-back'),
                        tooltip: 'Step back',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: replay.atStart ? null : replay.stepBack,
                      ),
                      IconButton.filled(
                        key: const ValueKey('replay-play'),
                        tooltip: replay.playing ? 'Pause' : 'Play',
                        icon: Icon(
                          replay.playing ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed:
                            replay.length == 0 ? null : replay.togglePlay,
                      ),
                      IconButton(
                        key: const ValueKey('replay-forward'),
                        tooltip: 'Step forward',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: replay.atEnd ? null : replay.stepForward,
                      ),
                      IconButton(
                        key: const ValueKey('replay-end'),
                        tooltip: 'Jump to end',
                        icon: const Icon(Icons.skip_next),
                        onPressed: replay.atEnd ? null : replay.toEnd,
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        key: const ValueKey('replay-speed'),
                        onPressed: _cycleSpeed,
                        child: Text('${replay.speed.round()}x'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 1x -> 2x -> 4x -> 1x.
  void _cycleSpeed() {
    const speeds = ReplayController.speeds;
    final at = speeds.indexOf(replay.speed);
    replay.speed = speeds[(at + 1) % speeds.length];
  }
}
