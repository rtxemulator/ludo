import 'package:flutter/material.dart';

/// Shows [child] in a [side] x [side] square turned by [turns] quarter turns
/// clockwise, animating (250 ms) the shortest way when [turns] changes. Used
/// for shared UI that faces the active seat (UI/UX doc section 3).
class TurnedBox extends StatefulWidget {
  const TurnedBox({
    super.key,
    required this.turns,
    required this.side,
    required this.child,
    this.animate = true,
  });

  final int turns;
  final double side;
  final Widget child;
  final bool animate;

  @override
  State<TurnedBox> createState() => _TurnedBoxState();
}

class _TurnedBoxState extends State<TurnedBox> {
  /// Accumulated quarter turns (may leave `0..3` so the animation never
  /// spins the long way round).
  late int _cumulative = widget.turns;

  @override
  void didUpdateWidget(TurnedBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    var delta = ((widget.turns - _cumulative) % 4 + 4) % 4;
    if (delta > 2) {
      delta -= 4;
    }
    _cumulative += delta;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: _cumulative / 4,
      duration:
          widget.animate ? const Duration(milliseconds: 250) : Duration.zero,
      curve: Curves.easeInOut,
      child: SizedBox.square(dimension: widget.side, child: widget.child),
    );
  }
}
