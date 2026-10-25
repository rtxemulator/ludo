import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/ai/ai.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/ui/core/motion_spec.dart';

import 'package:ludo_app/game/game_controller.dart';
import 'package:ludo_app/ui/setup/setup_screen.dart';

const levels = [
  AiLevel.easy,
  AiLevel.medium,
  AiLevel.hard,
  AiLevel.expert,
];

MatchSetup allAi() {
  var setup = MatchSetup.hotSeat();
  for (final seat in setup.activeSeats) {
    setup = setup.withSeat(seat, const SeatConfig.ai());
  }
  return setup;
}

MatchSetup mixedLevels() {
  var setup = MatchSetup.hotSeat();
  for (final seat in setup.activeSeats) {
    setup = setup.withSeat(seat, SeatConfig.ai(level: levels[seat]));
  }
  return setup;
}

Finder level(int seat, String label) => find.descendant(
      of: find.byKey(ValueKey('ai-level-$seat')),
      matching: find.text(label),
    );

/// A game on scripted backends that answer at once; returns the levels the
/// worker was asked for, per seat, after [frames] frames of play.
Map<int, Set<AiLevel>> askedLevels(
  MatchSetup setup, {
  bool rematch = false,
  int frames = 40000,
}) {
  final asked = <int, Set<AiLevel>>{};
  var t = 0.0;
  final driver = AiTurnDriver(
    backend: (sink) => _Instant(sink, (r) {
      asked.putIfAbsent(r.state.currentSeat, () => {}).add(r.level);
    }),
  );
  final game = GameController(
    setup: setup,
    seed: 11,
    now: () => t,
    haptics: false,
    aiDriver: driver,
  )..spec = MotionSpec.reduced;
  if (rematch) {
    game.newGame(seed: 12);
  }
  for (var i = 0; i < frames; i++) {
    t += 16;
    game.tick();
  }
  game.dispose();
  return asked;
}

class _Instant implements AiBackend {
  _Instant(this.sink, this.onRequest);

  final AiResponseSink sink;
  final void Function(AiRequest) onRequest;
  bool closed = false;

  @override
  bool get alive => !closed;

  @override
  void send(AiRequest request) {
    onRequest(request);
    sink(AiResponse(request.id, 0));
  }

  @override
  void close() => closed = true;
}

void main() {
  Future<MatchSetup?> playFrom(
    WidgetTester tester,
    MatchSetup initial,
    Future<void> Function() edit,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    MatchSetup? played;
    await tester.pumpWidget(
      MaterialApp(
        home: SetupScreen(initial: initial, onPlay: (_, s) => played = s),
      ),
    );
    await edit();
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    return played;
  }

  testWidgets('only AI seats get a picker, defaulting to Medium',
      (tester) async {
    final setup = MatchSetup.hotSeat().withSeat(1, const SeatConfig.ai());
    await playFrom(tester, setup, () async {});
    expect(find.byKey(const ValueKey('ai-level-1')), findsOneWidget);
    for (final seat in [0, 2, 3]) {
      expect(find.byKey(ValueKey('ai-level-$seat')), findsNothing);
    }
    final picker = tester.widget<SegmentedButton<AiLevel>>(
      find.byKey(const ValueKey('ai-level-1')),
    );
    expect(picker.selected, {AiLevel.medium});
    for (final label in ['Easy', 'Medium', 'Hard', 'Expert']) {
      expect(level(1, label), findsOneWidget);
    }
  });

  testWidgets('switching a seat to AI shows the picker', (tester) async {
    await playFrom(tester, MatchSetup.hotSeat(), () async {
      expect(find.byKey(const ValueKey('ai-level-0')), findsNothing);
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('seat-0')),
        matching: find.text('AI'),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('ai-level-0')), findsOneWidget);
    });
  });

  testWidgets('each level has its own line; Hard and Expert are called close',
      (tester) async {
    await playFrom(tester, allAi(), () async {
      for (final entry in SetupScreen.levelText.entries) {
        await tester.tap(level(
            0, entry.key.name[0].toUpperCase() + entry.key.name.substring(1)));
        await tester.pump();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('ai-level-text-0')))
              .data,
          entry.value,
        );
      }
      expect(SetupScreen.levelText[AiLevel.easy], contains('forgives'));
      expect(SetupScreen.levelText[AiLevel.expert], contains('strongest'));
      expect(find.textContaining('close in strength'), findsOneWidget);
    });
  });

  testWidgets('a different level per seat reaches the played setup',
      (tester) async {
    final played = await playFrom(tester, allAi(), () async {
      await tester.tap(level(0, 'Easy'));
      await tester.tap(level(2, 'Hard'));
      await tester.tap(level(3, 'Expert'));
      await tester.pump();
    });
    expect(
      [for (final s in played!.activeSeats) played.configOf(s).aiLevel],
      [AiLevel.easy, AiLevel.medium, AiLevel.hard, AiLevel.expert],
    );
  });

  testWidgets('levels survive a trip back to the setup screen', (tester) async {
    MatchSetup? remembered;
    await tester.binding.setSurfaceSize(const Size(480, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: SetupScreen(
          initial: allAi(),
          onChanged: (s) => remembered = s,
          onPlay: (_, __) {}),
    ));
    await tester.tap(level(1, 'Expert'));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
      home: SetupScreen(initial: remembered, onPlay: (_, __) {}),
    ));
    final picker = tester.widget<SegmentedButton<AiLevel>>(
      find.byKey(const ValueKey('ai-level-1')),
    );
    expect(picker.selected, {AiLevel.expert});
  });

  testWidgets('the picker is labelled for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await playFrom(tester, allAi(), () async {});
    expect(find.bySemanticsLabel('Red AI level'), findsOneWidget);
    expect(find.bySemanticsLabel('Blue AI level'), findsOneWidget);
    handle.dispose();
  });

  test('levels survive the JSON a saved game stores', () {
    final back = MatchSetup.fromJson(mixedLevels().toJson());
    expect(
      [for (final s in back.activeSeats) back.configOf(s).aiLevel],
      levels,
    );
  });

  test('every AI seat is asked at its own level; Easy never asks', () {
    final asked = askedLevels(mixedLevels());
    expect(asked.containsKey(0), isFalse);
    expect(asked[1], {AiLevel.medium});
    expect(asked[2], {AiLevel.hard});
    expect(asked[3], {AiLevel.expert});
  });

  test('a rematch keeps the levels', () {
    final asked = askedLevels(mixedLevels(), rematch: true);
    expect(asked[1], {AiLevel.medium});
    expect(asked[2], {AiLevel.hard});
    expect(asked[3], {AiLevel.expert});
  });

  test('a setup restored from its saved JSON plays at the same levels', () {
    final restored = MatchSetup.fromJson(mixedLevels().toJson());
    final asked = askedLevels(restored);
    expect(asked[1], {AiLevel.medium});
    expect(asked[2], {AiLevel.hard});
    expect(asked[3], {AiLevel.expert});
  });
}
