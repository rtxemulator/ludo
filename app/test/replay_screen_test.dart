import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';

import 'package:ludo_app/game/game_controller.dart';
import 'package:ludo_app/game/replay_controller.dart';
import 'package:ludo_app/main.dart';
import 'package:ludo_app/settings/game_settings.dart';
import 'package:ludo_app/ui/replay/replay_screen.dart';
import 'package:ludo_app/ui/screens/game_screen.dart';

import 'save_fixtures.dart';

/// The ticker never lets the tree settle, so frames are pumped by hand and
/// the controllers run on this manual clock.
class _Clock {
  double t = 0;
  double now() => t;
}

final MatchSetup _quick =
    MatchSetup.hotSeat(players: 2, rules: const RulesConfig.quick());

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _frames(
  WidgetTester tester,
  _Clock clock,
  int n, {
  double ms = 100,
}) async {
  for (var i = 0; i < n; i++) {
    clock.t += ms;
    await tester.pump(const Duration(milliseconds: 16));
  }
}

ReplayController _controller(GameSave save, _Clock clock) => ReplayController(
      script: ReplayScript.of(save),
      clock: clock.now,
      haptics: false,
    );

Future<void> _pumpReplay(
  WidgetTester tester,
  ReplayController replay, {
  bool salvaged = false,
}) async {
  _phone(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: ReplayScreen(
        script: replay.script,
        salvaged: salvaged,
        controller: replay,
        settings: GameSettings(haptics: false),
      ),
    ),
  );
  await tester.pump();
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

bool _enabled(WidgetTester tester, String k) =>
    tester.widget<IconButton>(_key(k)).onPressed != null;

String _text(WidgetTester tester, String k) =>
    tester.widget<Text>(_key(k)).data!;

void main() {
  testWidgets('shows the start, then each step with who rolled what',
      (tester) async {
    final clock = _Clock();
    final save = playSave(id: 'a', at: day, decisions: 20);
    final replay = _controller(save, clock);
    await _pumpReplay(tester, replay);

    expect(_text(tester, 'replay-step-text'), 'Start of the game');
    expect(_text(tester, 'replay-position'), startsWith('Move 0 of 20'));
    expect(_enabled(tester, 'replay-back'), isFalse);
    expect(_enabled(tester, 'replay-start'), isFalse);
    expect(_enabled(tester, 'replay-forward'), isTrue);

    await tester.tap(_key('replay-forward'));
    await _frames(tester, clock, 1);
    final first = replay.script.step(1);
    expect(_text(tester, 'replay-position'), startsWith('Move 1 of 20'));
    expect(
      _text(tester, 'replay-position'),
      endsWith('Turn ${first.ready.turnNumber}'),
    );
    expect(_text(tester, 'replay-step-text'), contains('rolled ${first.dice}'));
    expect(_enabled(tester, 'replay-back'), isTrue);
    await _frames(tester, clock, 20); // let the hop finish

    await tester.tap(_key('replay-back'));
    await tester.pump();
    expect(_text(tester, 'replay-position'), startsWith('Move 0 of 20'));
    expect(replay.game.state, replay.script.at(0));
  });

  testWidgets('the scrubber, jumps and the end', (tester) async {
    final clock = _Clock();
    final replay =
        _controller(playSave(id: 'a', at: day, decisions: 20), clock);
    await _pumpReplay(tester, replay);

    tester.widget<Slider>(_key('replay-slider')).onChanged!(8);
    await tester.pump();
    expect(replay.position, 8);
    expect(replay.game.state, replay.script.at(8));
    expect(_text(tester, 'replay-position'), startsWith('Move 8 of 20'));

    await tester.drag(_key('replay-slider'), const Offset(300, 0));
    await tester.pump();
    expect(replay.position, greaterThan(8));

    await tester.tap(_key('replay-end'));
    await tester.pump();
    expect(replay.position, 20);
    expect(_enabled(tester, 'replay-forward'), isFalse);
    expect(_enabled(tester, 'replay-end'), isFalse);

    await tester.tap(_key('replay-start'));
    await tester.pump();
    expect(replay.position, 0);
  });

  testWidgets('play and pause, auto-pause at the end', (tester) async {
    final clock = _Clock();
    final replay = _controller(playSave(id: 'a', at: day, decisions: 6), clock);
    await _pumpReplay(tester, replay);

    await tester.tap(_key('replay-play'));
    await _frames(tester, clock, 1);
    expect(replay.playing, isTrue);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(_key('replay-play'));
    await tester.pump();
    expect(replay.playing, isFalse);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(_key('replay-play'));
    await _frames(tester, clock, 200);
    expect(replay.position, 6);
    expect(replay.playing, isFalse);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('speed cycles 1x, 2x, 4x', (tester) async {
    final clock = _Clock();
    final replay = _controller(playSave(id: 'a', at: day, decisions: 6), clock);
    await _pumpReplay(tester, replay);

    expect(find.text('1x'), findsOneWidget);
    for (final label in ['2x', '4x', '1x']) {
      await tester.tap(_key('replay-speed'));
      await tester.pump();
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(_key('replay-speed'));
    await tester.pump();
    expect(replay.speed, 2);
  });

  testWidgets('taps on the table do not play: no roll, no choice',
      (tester) async {
    final clock = _Clock();
    final replay = _controller(playSave(id: 'a', at: day, decisions: 6), clock);
    await _pumpReplay(tester, replay);
    final before = replay.game.state;

    await tester.tap(_key('dock-0'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(Scaffold)));
    await _frames(tester, clock, 20);
    expect(replay.game.state, before);
    expect(replay.game.phase, GamePhase.awaitingRoll);
    expect(replay.game.dice, isNull);
    expect(replay.position, 0);
  });

  testWidgets('a damaged save says it is only part of the game',
      (tester) async {
    final clock = _Clock();
    final replay = _controller(playSave(id: 'a', at: day, decisions: 9), clock);
    await _pumpReplay(tester, replay, salvaged: true);
    expect(
      tester.widget<Text>(_key('replay-notice')).data,
      allOf(contains('Damaged save'), contains('first 9 moves')),
    );
  });

  testWidgets('a whole replay has no notice', (tester) async {
    final clock = _Clock();
    final replay = _controller(playSave(id: 'a', at: day, decisions: 9), clock);
    await _pumpReplay(tester, replay);
    expect(_key('replay-notice'), findsNothing);
  });

  testWidgets('leaving mid-hop leaves no ticker or timer behind',
      (tester) async {
    final clock = _Clock();
    final replay =
        _controller(playSave(id: 'a', at: day, decisions: 20), clock);
    await _pumpReplay(tester, replay);
    await tester.tap(_key('replay-speed'));
    await tester.tap(_key('replay-play'));
    await _frames(tester, clock, 6);
    expect(replay.game.replayMoving || replay.position > 0, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    // The test framework fails the test here if a timer is still pending.
    replay.dispose();
  });

  testWidgets('a screen that owns its replay disposes it too', (tester) async {
    _phone(tester);
    final save = playSave(id: 'a', at: day, decisions: 12);
    await tester.pumpWidget(
      MaterialApp(
        home: ReplayScreen(
          script: ReplayScript.of(save),
          settings: GameSettings(haptics: false),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(_key('replay-play'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the close button goes back', (tester) async {
    _phone(tester);
    final clock = _Clock();
    final replay = _controller(playSave(id: 'a', at: day, decisions: 6), clock);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReplayScreen(
                    script: replay.script,
                    controller: replay,
                    settings: GameSettings(haptics: false),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ReplayScreen), findsOneWidget);
    await tester.tap(_key('replay-close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ReplayScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
    replay.dispose();
  });

  group('game over', () {
    GameController finished(_Clock clock, SaveWriteQueue? queue) {
      final g = GameController(
        setup: _quick,
        seed: 21,
        now: clock.now,
        haptics: false,
        saves: queue,
        wallClock: () => DateTime.utc(2026, 10, 30, 12),
      );
      for (var i = 0; i < 60000 && g.phase != GamePhase.gameOver; i++) {
        if (g.phase == GamePhase.awaitingRoll) {
          g.roll();
        } else if (g.phase == GamePhase.awaitingMove) {
          final m = g.legal.first;
          g.tapAt(g.resting[m.owner][m.tokenIndex]);
          if (g.variants.isNotEmpty) {
            g.tapAt(g.variantPoints.first);
          }
        }
        clock.t += 400;
        g.tick();
      }
      expect(g.phase, GamePhase.gameOver);
      return g;
    }

    testWidgets('"Watch replay" hands over the save of the game just played',
        (tester) async {
      _phone(tester);
      final clock = _Clock();
      final store = InMemorySaveStore();
      final queue = SaveWriteQueue(store);
      final game = finished(clock, queue);
      GameSave? watched;
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            controller: game,
            settings: GameSettings(haptics: false),
            onReplay: (save) => watched = save,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(_key('watch-replay'), findsOneWidget);
      await tester.tap(_key('watch-replay'));
      await tester.pump();
      expect(watched, isNotNull);
      expect(watched!.id, game.save!.id);
      expect(watched!.finished, isTrue);
      final opening = ReplayOpening.of(watched!);
      expect(opening.ok, isTrue);
      expect(opening.script!.endsInGameOver, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no button without a save or without a handler',
        (tester) async {
      _phone(tester);
      final clock = _Clock();
      final unsaved = finished(clock, null);
      expect(unsaved.save, isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            controller: unsaved,
            settings: GameSettings(haptics: false),
            onReplay: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Rematch'), findsOneWidget);
      expect(_key('watch-replay'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      final saved = finished(_Clock(), SaveWriteQueue(InMemorySaveStore()));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            controller: saved,
            settings: GameSettings(haptics: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Rematch'), findsOneWidget);
      expect(_key('watch-replay'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('app wiring', () {
    testWidgets('Saved Games opens a replay; closing it changes nothing',
        (tester) async {
      _phone(tester);
      final store = InMemorySaveStore();
      await store.put(playSave(
        id: 'done',
        at: day,
        toEnd: true,
        seed: 21,
        name: 'Won',
        setup: _quick,
      ));
      final before = (await store.list()).single;
      await tester.pumpWidget(LudoApp(library: SaveLibrary(store)));
      await tester.pump();
      await tester.tap(_key('home-saved'));
      await tester.pumpAndSettle();
      await tester.tap(_key('save-done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ReplayScreen), findsOneWidget);

      await tester.tap(_key('replay-close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ReplayScreen), findsNothing);
      expect(find.text('Saved Games'), findsOneWidget);

      final after = (await store.list()).single;
      expect(after.updatedAt, before.updatedAt);
      expect(after.moves, before.moves);
      expect(after.name, before.name);
    });
  });
}
