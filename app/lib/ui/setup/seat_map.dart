import 'package:flutter/material.dart';
import 'package:ludo/seats/seats.dart';

import '../theme/palette.dart';

/// A small picture of the table: the four board corners, filled in for the
/// seats that play (with who controls them and, in team play, the team), and
/// ghosted for the empty ones. It shows where everybody sits.
class SeatMap extends StatelessWidget {
  const SeatMap({super.key, required this.setup, required this.palette});

  final MatchSetup setup;
  final LudoPalette palette;

  static String _typeLabel(SeatType type) => switch (type) {
        SeatType.human => 'Human',
        SeatType.ai => 'AI',
        SeatType.remote => 'Online',
      };

  @override
  Widget build(BuildContext context) {
    const gap = 6.0;
    return AspectRatio(
      aspectRatio: 1,
      child: Column(
        children: [
          for (final row in const [
            [0, 1],
            [3, 2],
          ]) ...[
            if (row.first == 3) const SizedBox(height: gap),
            Expanded(
              child: Row(
                children: [
                  for (final seat in row) ...[
                    if (seat == row.last) const SizedBox(width: gap),
                    Expanded(child: _corner(context, seat)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _corner(BuildContext context, int seat) {
    final color = palette.seat[seat];
    final config = setup.seats[seat];
    final radius = BorderRadius.circular(14);
    if (config == null) {
      return DecoratedBox(
        key: ValueKey('map-$seat'),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: color.withAlpha(90), width: 2),
        ),
      );
    }
    final fill = color.withAlpha(235);
    final ink = ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return DecoratedBox(
      key: ValueKey('map-$seat'),
      decoration: BoxDecoration(color: fill, borderRadius: radius),
      child: Center(
        child: DefaultTextStyle(
          style: TextStyle(color: ink, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_typeLabel(config.type)),
              if (setup.isTeamPlay)
                Text(
                  setup.teamOf(seat) == 0 ? 'Team A' : 'Team B',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
