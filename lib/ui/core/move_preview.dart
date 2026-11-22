/// Move preview (polish pass, step 5): what a tap on a token shows before the
/// move is made. A ring where the token would land, a trail of dots over the
/// squares it would cross, and a distinct, double ring when the move captures.
/// Pure Dart, no Flutter.
///
/// The preview only *presents* what the engine already decided: it applies
/// the move to a copy of the state (`Engine.apply`) and reads the result; it
/// never decides a rule.
library;

import 'package:ludo/engine/ludo_engine.dart';

import 'board_geometry.dart';
import 'curves.dart';
import 'motion_spec.dart';
import 'pt.dart';

/// What the move does when it lands. A capture wins over a finish, a finish
/// over a yard exit.
enum PreviewKind { step, yardExit, home, capture }

/// One frame of the preview: how big the destination ring is and how visible.
class PreviewSample {
  const PreviewSample({required this.ringScale, required this.ringAlpha});

  final double ringScale;
  final double ringAlpha;
}

class MovePreview {
  const MovePreview._({
    required this.move,
    required this.kind,
    required this.origin,
    required this.destination,
    required this.trail,
    required this.captured,
  });

  /// Previews [move] taking [before] one step on.
  factory MovePreview.of(
    GameState before,
    Move move, {
    BoardGeometry geometry = const BoardGeometry(),
  }) {
    final after = Engine.apply(before, move);
    final owner = move.owner;
    final index = move.tokenIndex;
    final from = before.tokens[owner][index];
    final to = after.tokens[owner][index];
    final restBefore = geometry.restingPoints(before);
    final restAfter = geometry.restingPoints(after);

    // The squares crossed on the way (not the square it leaves, not the one
    // it lands on). A token leaving the yard just appears on its start
    // square, so it crosses nothing.
    final trail = <Pt>[];
    if (from != yardPosition) {
      for (var p = from + 1; p < to; p++) {
        trail.add(geometry.cellCenter(owner, p, index));
      }
    }

    final captured = <Pt>[];
    for (var seat = 0; seat < seatCount; seat++) {
      if (seat == owner) {
        continue;
      }
      for (var i = 0; i < tokensPerSeat; i++) {
        if (isOnTrack(before.tokens[seat][i]) &&
            after.tokens[seat][i] == yardPosition) {
          captured.add(restBefore[seat][i]);
        }
      }
    }

    final PreviewKind kind;
    if (captured.isNotEmpty) {
      kind = PreviewKind.capture;
    } else if (to == finishPosition) {
      kind = PreviewKind.home;
    } else if (from == yardPosition) {
      kind = PreviewKind.yardExit;
    } else {
      kind = PreviewKind.step;
    }

    return MovePreview._(
      move: move,
      kind: kind,
      origin: restBefore[owner][index],
      destination: restAfter[owner][index],
      trail: List<Pt>.unmodifiable(trail),
      captured: List<Pt>.unmodifiable(captured),
    );
  }

  final Move move;
  final PreviewKind kind;

  /// Where the token is now and where it would rest (board cells).
  final Pt origin;
  final Pt destination;

  /// Centres of the squares crossed, in walking order.
  final List<Pt> trail;

  /// Squares of the opponent tokens this move would send home.
  final List<Pt> captured;

  bool get isCapture => kind == PreviewKind.capture;

  /// Whether this previews token ([owner], [index]).
  bool isFor(int owner, int index) => move.owner == owner && move.moves(index);

  // ---- Numbers the painter uses (cells) -----------------------------------

  /// Destination ring radius, stroke, and the extra outer ring of a capture.
  static const double ringRadius = 0.52;
  static const double ringStroke = 0.09;
  static const double captureOuterRadius = 0.7;
  static const double captureStroke = 0.07;

  /// Four ticks pointing out of a capture's outer ring.
  static const double tickInner = 0.78;
  static const double tickOuter = 0.98;

  /// Trail dot radius.
  static const double dotRadius = 0.085;

  // ---- Timing --------------------------------------------------------------

  /// The ring pops in over this long; trail dots appear one after another.
  static const double popMs = 160;
  static const double dotStaggerMs = 35;
  static const double dotFadeMs = 120;

  /// The ring at [sinceMs] after the preview opened: it grows from 0.6 with a
  /// small overshoot (`easeOutBack`) and fades in. Reduced motion: at once.
  PreviewSample look(double sinceMs, MotionSpec spec) {
    if (spec.reducedMotion) {
      return const PreviewSample(ringScale: 1, ringAlpha: 1);
    }
    final u = clamp01(sinceMs / popMs);
    return PreviewSample(
      ringScale: 0.6 + 0.4 * easeOutBack(u),
      ringAlpha: clamp01(u * 2),
    );
  }

  /// Opacity of trail dot [i] at [sinceMs] (`0..1`).
  double dotAlpha(int i, double sinceMs, MotionSpec spec) {
    if (spec.reducedMotion) {
      return 1;
    }
    return clamp01((sinceMs - i * dotStaggerMs) / dotFadeMs);
  }

  /// When the whole preview has finished appearing.
  double get settledMs =>
      trail.isEmpty ? popMs : trail.length * dotStaggerMs + dotFadeMs;
}
