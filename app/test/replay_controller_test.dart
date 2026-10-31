import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';

import 'package:ludo_app/game/game_controller.dart';
import 'package:ludo_app/game/replay_controller.dart';
import 'package:ludo_app/ui/replay/replay_text.dart';

import 'save_fixtures.dart';

/// A replay on a manual clock.
class _Rig {
  _Rig(GameSave save)
      : script = ReplayScript.of(save),
        timeline = SaveReplayer.timeline(save) {
    replay = ReplayController(
      script: script,
      clock: () => t,
      haptics: false,
    );
  }

  final ReplayScript script;
  final SaveTimeline timeline;
  late final ReplayController replay;
  double t = 0;

  GameController get game => replay.game;

  /// Runs frames (16 ms apart) until nothing is animating.
  void settle() {
    for (var i = 0; i < 4000 && game.replayMoving; i++) {
      t += 16;
      replay.tick();
    }
    expect(game.replayMoving, isFalse, reason: 'a move never finished');
  }

  /// Runs frames for [ms] of real time.
  void run(double ms) {
    final end = t + ms;
    while (t < end) {
      t += 16;
      replay.tick();
    }
  }

  /// Plays until playback stops by itself; returns the real ms it took.
  double playToEnd() {
    final start = t;
    replay.play();
    for (var i = 0; i < 200000 && replay.playing; i++) {
      t += 16;
      replay.tick();
    }
    expect(replay.playing, isFalse, reason: 'playback never stopped');
    return t - start;
  }
}

GameSave _plain({int decisions = 30, int seed = 11}) => playSave(
      id: 'plain',
      at: day,
      decisions: decisions,
      seed: seed,
    );

GameSave _finished() => playSave(
      id: 'done',
      at: day,
      toEnd: true,
      seed: 21,
      setup: MatchSetup.hotSeat(players: 2, rules: const RulesConfig.quick()),
    );

/// A banked game that has a decision in the middle of spending a bank.
GameSave _bankedMidSpend() {
  final setup = MatchSetup.hotSeat(
    players: 2,
    rules: const RulesConfig(bankedRolls: true),
  );
  for (var seed = 1; seed < 60; seed++) {
    final save = playSave(
      id: 'b$seed',
      at: day,
      decisions: 60,
      seed: seed,
      setup: setup,
    );
    final script = ReplayScript.of(save);
    for (var k = 1; k <= script.length; k++) {
      final s = script.step(k);
      if (s.before.awaitingMove && s.ready.bank.length >= 2) {
        return save;
      }
    }
  }
  fail('no banked game with a mid-spend decision found');
}

/// A team game with a finished player rolling for the partner.
GameSave _teamControl() {
  final setup = MatchSetup.hotSeat(teams: true);
  for (var seed = 1; seed < 20; seed++) {
    final save = playSave(
      id: 't$seed',
      at: day,
      toEnd: true,
      seed: seed,
      setup: setup,
    );
    final script = ReplayScript.of(save);
    for (var k = 1; k <= script.length; k++) {
      if (script.step(k).move.owner != script.step(k).roller) {
        return save;
      }
    }
  }
  fail('no team game with teammate control found');
}

int _firstStep(ReplayScript script, bool Function(ReplayStep) test) {
  for (var k = 1; k <= script.length; k++) {
    if (test(script.step(k))) {
      return k;
    }
  }
  fail('no such step');
}

void main() {
  group('stepping', () {
    test('forward loads the state before the decision, then plays it', () {
      final rig = _Rig(_plain());
      expect(rig.replay.position, 0);
      expect(rig.game.state, rig.script.at(0));
      for (var k = 1; k <= rig.script.length; k++) {
        rig.replay.stepForward();
        expect(rig.replay.position, k);
        // The hop is running from the state just before the move.
        expect(rig.game.replayMoving, isTrue, reason: 'step $k');
        expect(rig.game.state, rig.script.step(k).ready, reason: 'step $k');
        rig.settle();
        expect(rig.game.state, rig.script.at(k), reason: 'step $k');
      }
      expect(rig.replay.atEnd, isTrue);
    });

    test('back and scrubbing jump without animation', () {
      final rig = _Rig(_plain());
      rig.replay.toEnd();
      expect(rig.game.replayMoving, isFalse);
      expect(rig.game.state, rig.script.at(rig.script.length));
      for (var k = rig.script.length - 1; k >= 0; k--) {
        rig.replay.stepBack();
        expect(rig.game.replayMoving, isFalse);
        expect(rig.game.state, rig.script.at(k), reason: 'back to $k');
        expect(rig.replay.position, k);
      }
      expect(rig.replay.atStart, isTrue);
      for (final k in [7, 3, 19, 0, 30, 12]) {
        rig.replay.seek(k);
        expect(rig.game.replayMoving, isFalse);
        expect(rig.game.state, rig.script.at(k), reason: 'seek $k');
      }
      rig.replay.seek(999);
      expect(rig.replay.position, rig.script.length);
      rig.replay.seek(-5);
      expect(rig.replay.position, 0);
    });

    test('a manual step while a move is hopping settles it first', () {
      final rig = _Rig(_plain());
      rig.replay.stepForward();
      rig.run(50);
      expect(rig.game.replayMoving, isTrue);
      rig.replay.stepForward();
      expect(rig.replay.position, 2);
      expect(rig.game.state, rig.script.step(2).ready);
      rig.settle();
      expect(rig.game.state, rig.script.at(2));
    });

    test('scrubbing in the middle of a hop drops the hop', () {
      final rig = _Rig(_plain());
      rig.replay.stepForward();
      rig.run(50);
      rig.replay.seek(0);
      expect(rig.game.replayMoving, isFalse);
      expect(rig.game.state, rig.script.at(0));
      // Nothing is left to finish later and change the state.
      rig.run(2000);
      expect(rig.game.state, rig.script.at(0));
      expect(rig.replay.position, 0);
    });

    test('property: the whole timeline forward, then back, equals it', () {
      final setups = <String, MatchSetup>{
        'plain 2p': MatchSetup.hotSeat(players: 2),
        'classic 4p': MatchSetup.hotSeat(),
        'teams': MatchSetup.hotSeat(teams: true),
        'banked 4p': MatchSetup.hotSeat(
          rules: const RulesConfig(bankedRolls: true),
        ),
        'strategic': MatchSetup.hotSeat(rules: const RulesConfig.strategic()),
      };
      for (final entry in setups.entries) {
        final rig = _Rig(
          playSave(
            id: entry.key,
            at: day,
            decisions: 70,
            seed: 5,
            setup: entry.value,
          ),
        );
        final expected = rig.timeline.states;
        final seen = <GameState>[rig.game.state];
        while (!rig.replay.atEnd) {
          rig.replay.stepForward();
          rig.settle();
          seen.add(rig.game.state);
        }
        expect(seen, expected, reason: '${entry.key} forward');
        final back = <GameState>[rig.game.state];
        while (!rig.replay.atStart) {
          rig.replay.stepBack();
          back.add(rig.game.state);
        }
        expect(back.reversed.toList(), expected, reason: '${entry.key} back');
      }
    });
  });

  group('banked rolls', () {
    test('a decision in the middle of a bank shows the chips left', () {
      final save = _bankedMidSpend();
      final rig = _Rig(save);
      final k = _firstStep(
        rig.script,
        (s) => s.before.awaitingMove && s.ready.bank.length >= 2,
      );
      final step = rig.script.step(k);
      rig.replay.seek(k - 1);
      // Mid-spend: the tray holds what is still unspent.
      expect(rig.game.state.awaitingMove, isTrue);
      expect(
        rig.game.tray.valuesOf(step.roller),
        rig.script.at(k - 1).bank,
      );

      rig.replay.stepForward();
      expect(rig.game.tray.presentOf(step.roller),
          hasLength(step.ready.bank.length - 1));
      rig.settle();
      expect(rig.game.state, rig.script.at(k));
      expect(rig.game.tray.valuesOf(step.roller), step.after.bank);
      // The replay never turns into a move choice.
      expect(rig.game.choice, isNull);
      expect(rig.game.legal, isEmpty);
    });

    test('every state of a banked game shows its own bank', () {
      final rig = _Rig(_bankedMidSpend());
      for (var k = 0; k <= rig.script.length; k++) {
        rig.replay.seek(k);
        final s = rig.script.at(k);
        expect(rig.game.tray.valuesOf(s.currentSeat), s.bank, reason: '$k');
        expect(rig.game.choice, isNull);
      }
    });
  });

  group('teams with teammate control', () {
    test('the finished roller moves the partner\'s tokens', () {
      final rig = _Rig(_teamControl());
      final k = _firstStep(rig.script, (s) => s.move.owner != s.roller);
      final step = rig.script.step(k);
      rig.replay.seek(k - 1);
      rig.replay.stepForward();
      expect(rig.game.state.currentSeat, step.roller);
      expect(rig.game.rollerSeat, step.roller);
      expect(rig.game.activeSeat, step.roller);
      rig.settle();
      expect(rig.game.state, rig.script.at(k));
      expect(
        describeStep(step, rig.script.save.setup),
        contains("${rig.script.save.setup.displayName(step.move.owner)}'s"),
      );
    });

    test('every step of the game replays', () {
      final rig = _Rig(_teamControl());
      for (var k = 1; k <= rig.script.length; k += 7) {
        rig.replay.seek(k - 1);
        rig.replay.stepForward();
        rig.settle();
        expect(rig.game.state, rig.script.at(k), reason: 'step $k');
      }
    });
  });

  group('finished game', () {
    test('the end shows the result without confetti, stepping stops', () {
      final rig = _Rig(_finished());
      rig.replay.toEnd();
      expect(rig.game.phase, GamePhase.gameOver);
      expect(rig.game.state.isOver, isTrue);
      expect(rig.game.winnerSeat, isNotNull);
      expect(rig.game.confetti, isNull);
      rig.replay.stepForward();
      expect(rig.replay.position, rig.script.length);
      expect(rig.game.replayMoving, isFalse);
      rig.replay.stepBack();
      expect(rig.game.phase, isNot(GamePhase.gameOver));
    });

    test('playing the last decision ends in game over and pauses', () {
      final rig = _Rig(_finished());
      rig.replay.seek(rig.script.length - 1);
      rig.replay.stepForward();
      rig.settle();
      expect(rig.game.phase, GamePhase.gameOver);
      expect(rig.game.winnerSeat, isNotNull);
    });
  });

  group('playback', () {
    test('play runs to the end by itself and pauses there', () {
      final rig = _Rig(_plain(decisions: 12));
      rig.playToEnd();
      expect(rig.replay.atEnd, isTrue);
      expect(rig.replay.playing, isFalse);
      expect(rig.game.state, rig.script.at(12));
    });

    test('play at the end starts over', () {
      final rig = _Rig(_plain(decisions: 6));
      rig.playToEnd();
      rig.replay.play();
      expect(rig.replay.position, 0);
      expect(rig.replay.playing, isTrue);
      rig.run(1500);
      expect(rig.replay.position, greaterThan(0));
    });

    test('pause holds the position', () {
      final rig = _Rig(_plain(decisions: 20));
      rig.replay.play();
      rig.run(3000);
      expect(rig.replay.position, greaterThan(0));
      rig.replay.pause();
      rig.settle();
      final at = rig.replay.position;
      rig.run(5000);
      expect(rig.replay.position, at);
      expect(rig.replay.playing, isFalse);
    });

    test('speed 2x and 4x take proportionally less time', () {
      final times = <double, double>{};
      for (final speed in ReplayController.speeds) {
        final rig = _Rig(_plain(decisions: 10));
        rig.replay.speed = speed;
        times[speed] = rig.playToEnd();
        expect(rig.replay.position, 10);
      }
      expect(times[2]!, lessThan(times[1]! * 0.65));
      expect(times[4]!, lessThan(times[1]! * 0.35));
      expect(times[4]!, lessThan(times[2]!));
    });

    test('changing speed while playing keeps going', () {
      final rig = _Rig(_plain(decisions: 10));
      rig.replay.play();
      rig.run(800);
      rig.replay.speed = 4;
      expect(rig.replay.speed, 4);
      rig.playToEnd();
      expect(rig.replay.position, 10);
    });

    test('manual controls pause playback', () {
      final rig = _Rig(_plain());
      rig.replay.play();
      rig.replay.stepBack();
      expect(rig.replay.playing, isFalse);
      rig.replay.play();
      rig.replay.seek(5);
      expect(rig.replay.playing, isFalse);
      rig.replay.play();
      rig.replay.stepForward();
      expect(rig.replay.playing, isFalse);
    });
  });

  group('presentation model only', () {
    test('no roll, tap or AI turn does anything', () {
      final rig = _Rig(
        playSave(
          id: 'ai',
          at: day,
          decisions: 10,
          setup: MatchSetup.hotSeat(players: 2)
              .withSeat(2, const SeatConfig.ai(level: AiLevel.hard)),
        ),
      );
      final game = rig.game;
      expect(game.isReplay, isTrue);
      final before = game.state;
      game.roll();
      game.dockTap(game.state.currentSeat);
      game.quickRoll();
      expect(game.tapAt(game.resting[0][0]), isFalse);
      rig.run(5000);
      expect(game.phase, GamePhase.awaitingRoll);
      expect(game.state, before);
      expect(game.dice, isNull);
      expect(game.save, isNull);
      expect(game.moveLog, isEmpty);
    });

    test('a whole replay writes nothing to the store', () async {
      final store = _CountingStore();
      final library = SaveLibrary(store);
      await store.inner.put(_finished());
      await store.inner.put(_plain());
      final before = await store.inner.list();
      for (final item in before) {
        final opening = await library.openReplay(item);
        final rig = _Rig(opening.script!.save);
        rig.playToEnd();
        rig.replay.seek(3);
        rig.replay.stepForward();
        rig.settle();
        rig.replay.toEnd();
        rig.replay.dispose();
      }
      await library.queue.flush();
      expect(store.writes, 0);
      final after = await store.inner.list();
      expect(
        after.map((r) => (r.id, r.updatedAt, r.moves)).toList(),
        before.map((r) => (r.id, r.updatedAt, r.moves)).toList(),
      );
    });
  });

  group('leaving', () {
    test('disposing mid-hop is clean and later frames are ignored', () {
      final rig = _Rig(_plain());
      rig.replay.play();
      rig.run(600);
      rig.replay.dispose();
      rig.t += 100;
      expect(rig.replay.tick, returnsNormally);
    });
  });

  group('describeStep', () {
    test('says who rolled what and which token moved', () {
      final save = _plain();
      final script = ReplayScript.of(save);
      final step = script.step(1);
      final text = describeStep(step, save.setup);
      expect(text, contains('rolled ${step.dice}'));
      expect(text, contains('token ${step.move.tokenIndex + 1}'));
      expect(text, startsWith(save.setup.displayName(step.roller)));
    });
  });
}

/// A store that counts every write.
class _CountingStore implements SaveStore {
  final InMemorySaveStore inner = InMemorySaveStore();
  int writes = 0;

  @override
  Future<void> put(GameSave save) async {
    writes++;
    await inner.put(save);
  }

  @override
  Future<bool> rename(String id, String name) {
    writes++;
    return inner.rename(id, name);
  }

  @override
  Future<bool> delete(String id) {
    writes++;
    return inner.delete(id);
  }

  @override
  Future<List<SaveListItem>> list() => inner.list();

  @override
  Future<SaveDecode?> get(String id) => inner.get(id);
}
