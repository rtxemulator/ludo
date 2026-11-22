import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/move_preview.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

MovePreview previewOf(GameState state, int tokenIndex) {
  final move = Engine.legalMoves(state).singleWhere(
    (m) => m.tokenIndex == tokenIndex,
  );
  return MovePreview.of(state, move);
}

void main() {
  const geo = BoardGeometry();

  test('a plain move: ring on the landing square, dots on the squares between',
      () {
    final state = makeState(tokens: {
      0: [2, -1, -1, -1],
    }, dice: 3);
    final p = previewOf(state, 0);
    expect(p.kind, PreviewKind.step);
    expect(p.origin, geo.trackCell(2));
    expect(p.destination, geo.trackCell(5));
    expect(p.trail, [geo.trackCell(3), geo.trackCell(4)]);
    expect(p.captured, isEmpty);
    expect(p.isCapture, isFalse);
  });

  test('leaving the yard crosses nothing', () {
    final state = makeState(dice: 6);
    final p = previewOf(state, 0);
    expect(p.kind, PreviewKind.yardExit);
    expect(p.origin, geo.yardSpot(0, 0));
    expect(p.destination, geo.trackCell(0));
    expect(p.trail, isEmpty);
  });

  test('a capture is its own kind and names the squares it empties', () {
    // Seat 2's token on absolute square 12 (relative 38), not a safe square.
    final state = makeState(tokens: {
      0: [9, -1, -1, -1],
      2: [38, -1, -1, -1],
    }, dice: 3);
    final p = previewOf(state, 0);
    expect(p.kind, PreviewKind.capture);
    expect(p.isCapture, isTrue);
    expect(p.captured, [geo.trackCell(12)]);
    expect(p.destination, geo.trackCell(12));
    expect(p.trail, [geo.trackCell(10), geo.trackCell(11)]);
  });

  test('landing on a safe square next to an opponent is no capture', () {
    // Absolute square 13 is seat 1's start square.
    final state = makeState(tokens: {
      0: [10, -1, -1, -1],
      1: [0, -1, -1, -1],
    }, dice: 3);
    final p = previewOf(state, 0);
    expect(p.kind, PreviewKind.step);
    expect(p.captured, isEmpty);
  });

  test('reaching the finish square is a home preview', () {
    final state = makeState(tokens: {
      0: [53, -1, -1, -1],
    }, dice: 3);
    final p = previewOf(state, 0);
    expect(p.kind, PreviewKind.home);
    expect(p.destination, geo.finishSlot(0, 0));
    expect(p.trail, [geo.homeCell(0, 54), geo.homeCell(0, 55)]);
  });

  test('the preview never changes the state it reads', () {
    final state = makeState(tokens: {
      0: [2, -1, -1, -1],
    }, dice: 3);
    final before = state.tokens.map((t) => [...t]).toList();
    previewOf(state, 0);
    expect(state.tokens, before);
  });

  test('isFor matches the previewed token only', () {
    final state = makeState(tokens: {
      0: [2, 5, -1, -1],
    }, dice: 3);
    final p = previewOf(state, 0);
    expect(p.isFor(0, 0), isTrue);
    expect(p.isFor(0, 1), isFalse);
    expect(p.isFor(1, 0), isFalse);
  });

  test('the ring pops in and the dots follow one after another', () {
    final state = makeState(tokens: {
      0: [2, -1, -1, -1],
    }, dice: 3);
    final p = previewOf(state, 0);
    const spec = MotionSpec.standard;
    final start = p.look(0, spec);
    final end = p.look(MovePreview.popMs, spec);
    expect(start.ringAlpha, 0);
    expect(start.ringScale, closeTo(0.6, 1e-9));
    expect(end.ringAlpha, 1);
    expect(end.ringScale, closeTo(1, 1e-9));
    expect(p.dotAlpha(0, 0, spec), 0);
    expect(p.dotAlpha(0, MovePreview.dotFadeMs, spec), 1);
    // The second dot starts later than the first.
    expect(
      p.dotAlpha(1, MovePreview.dotStaggerMs, spec),
      lessThan(p.dotAlpha(0, MovePreview.dotStaggerMs, spec)),
    );
    expect(p.settledMs, 2 * MovePreview.dotStaggerMs + MovePreview.dotFadeMs);
  });

  test('reduced motion shows everything at once', () {
    final state = makeState(tokens: {
      0: [2, -1, -1, -1],
    }, dice: 3);
    final p = previewOf(state, 0);
    final s = p.look(0, MotionSpec.reduced);
    expect(s.ringScale, 1);
    expect(s.ringAlpha, 1);
    expect(p.dotAlpha(1, 0, MotionSpec.reduced), 1);
  });
}
