import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/ai/ai.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';
import 'package:ludo/ui/core/motion_spec.dart';

import 'package:ludo_app/game/game_controller.dart';

const _banked = RulesConfig(bankedRolls: true);

/// A store whose writes always fail.
class _FailingStore implements SaveStore {
  final InMemorySaveStore _inner = InMemorySaveStore();

  @override
  Future<void> put(GameSave save) async => throw StateError('disk full');

  @override
  Future<List<SaveListItem>> list() => _inner.list();

  @override
  Future<SaveDecode?> get(String id) => _inner.get(id);

  @override
  Future<bool> rename(String id, String name) => _inner.rename(id, name);

  @override
  Future<bool> delete(String id) => _inner.delete(id);
}

/// A hot-seat game on a manual clock, autosaving into [queue].
class _Rig {
  _Rig({
    MatchSetup? setup,
    int? seed = 3,
    required this.queue,
    GameSave? resumeFrom,
    AiTurnDriver? aiDriver,
  }) {
    game = GameController(
      setup: setup,
      seed: seed,
      now: () => t,
      haptics: false,
      saves: queue,
      wallClock: () => DateTime.utc(2026, 10, 30, 12).add(
        Duration(seconds: wallSeconds++),
      ),
      resumeFrom: resumeFrom,
      aiDriver: aiDriver,
    );
  }

  final SaveWriteQueue queue;
  late final GameController game;
  double t = 0;
  int wallSeconds = 0;

  void step([double ms = 400]) {
    t += ms;
    game.tick();
  }

  /// "First legal move" for whichever human decision is pending.
  void act() {
    final g = game;
    if (g.phase == GamePhase.awaitingRoll) {
      g.roll();
    } else if (g.phase == GamePhase.awaitingMove) {
      final Move m;
      if (g.banked) {
        final c = g.choice!;
        m = c.legal.first;
        if (c.selected != m.dieIndex) {
          g.chipTap(g.state.currentSeat, m.dieIndex);
        }
      } else {
        m = g.legal.first;
      }
      g.tapAt(g.resting[m.owner][m.tokenIndex]);
      if (g.variants.isNotEmpty) {
        g.tapAt(g.variantPoints.first);
      }
    }
  }

  bool get settled =>
      game.phase == GamePhase.awaitingRoll ||
      game.phase == GamePhase.awaitingMove ||
      game.phase == GamePhase.gameOver;

  /// Plays until [done] holds on a settled table.
  void runUntil(bool Function() done, {int maxSteps = 40000}) {
    for (var i = 0; i < maxSteps; i++) {
      if (settled && done()) {
        return;
      }
      step();
      act();
    }
    fail('never reached the wanted position');
  }

  /// Plays until [n] decisions are logged and the last one has finished.
  void runDecisions(int n) => runUntil(() => game.moveLog.length >= n);
}

SaveWriteQueue _queue([SaveStore? store]) =>
    SaveWriteQueue(store ?? InMemorySaveStore());

Future<GameSave> _stored(SaveWriteQueue queue, String id) async {
  await queue.flush();
  return (await queue.store.get(id))!.save!;
}

void main() {
  test('no save exists before the first decision', () async {
    final queue = _queue();
    final rig = _Rig(queue: queue);
    expect(rig.game.save, isNull);
    rig.act(); // starts the roll; no decision has been made yet
    expect(rig.game.phase, GamePhase.rolling);
    await queue.flush();
    expect(await queue.store.list(), isEmpty);
    expect(rig.game.save, isNull);
    expect(rig.game.moveLog, isEmpty);
  });

  test('every decision is saved: log, seed and a replayable state', () async {
    final queue = _queue();
    final rig = _Rig(queue: queue, seed: 3);
    rig.runDecisions(1);
    final id = rig.game.save!.id;
    expect(await queue.store.list(), hasLength(1));

    rig.runDecisions(6);
    final save = await _stored(queue, id);
    expect(save.id, id);
    expect(save.seed, 3);
    expect(rig.game.seed, 3);
    expect(save.moves, rig.game.moveLog.length);
    expect(save.moves, 6);
    final replay = SaveReplayer.replay(save);
    expect(replay.ok, isTrue);
    expect(replay.state, rig.game.state);
    expect(await queue.store.list(), hasLength(1));
  });

  test('the save keeps the setup and the seed drawn from the clock', () async {
    final queue = _queue();
    final setup = MatchSetup.hotSeat(players: 2);
    final rig = _Rig(setup: setup, queue: queue, seed: null);
    expect(rig.game.seed, inInclusiveRange(0, 0x7fffffff));
    rig.runDecisions(1);
    final save = await _stored(queue, rig.game.save!.id);
    expect(save.seed, rig.game.seed);
    expect(save.setup, setup);
    expect(SaveReplayer.replay(save).ok, isTrue);
  });

  test('newGame and rematch start a new save and keep the old one', () async {
    final queue = _queue();
    final rig = _Rig(queue: queue, seed: 5);
    rig.runDecisions(3);
    final first = rig.game.save!;

    rig.game.newGame();
    expect(rig.game.save, isNull);
    expect(rig.game.moveLog, isEmpty);
    final drawn = rig.game.seed;
    expect(drawn, isNot(5));

    rig.runDecisions(2);
    final second = rig.game.save!;
    expect(second.id, isNot(first.id));
    expect(second.seed, drawn);
    expect(second.moves, 2);

    rig.game.rematch();
    expect(rig.game.save, isNull);
    rig.runDecisions(1);
    expect(rig.game.save!.id, isNot(second.id));

    await queue.flush();
    final items = await queue.store.list();
    expect(items, hasLength(3));
    expect((await _stored(queue, first.id)).moves, 3);
    expect((await _stored(queue, second.id)).moves, 2);
  });

  test('a rule change mid-game starts a new save and keeps the old', () async {
    final queue = _queue();
    final rig = _Rig(queue: queue, seed: 8);
    rig.runDecisions(2);
    final before = rig.game.save!;

    rig.game.setBankedRolls(true);
    expect(rig.game.save, isNull);
    rig.runDecisions(1);
    final after = rig.game.save!;
    expect(after.id, isNot(before.id));
    expect(after.setup.rules.bankedRolls, isTrue);
    expect((await _stored(queue, before.id)).setup.rules.bankedRolls, isFalse);
  });

  test('resume restores the state and continues the same save', () async {
    final queue = _queue();
    final a = _Rig(queue: queue, seed: 21);
    a.runDecisions(8);
    final saved = await _stored(queue, a.game.save!.id);

    final b = _Rig(queue: queue, seed: 999, resumeFrom: saved);
    expect(b.game.state, a.game.state);
    expect(b.game.phase, GamePhase.awaitingRoll);
    expect(b.game.save!.id, saved.id);
    expect(b.game.seed, 21);
    expect(b.game.moveLog.length, 8);
    expect(b.game.dice, isNull);

    b.runDecisions(16);
    expect((await _stored(queue, saved.id)).moves, 16);
    expect(await queue.store.list(), hasLength(1));

    // The same game, never interrupted, ends up in the same place.
    final c = _Rig(queue: _queue(), seed: 21);
    c.runDecisions(16);
    expect(b.game.state, c.game.state);
    expect(b.game.moveLog.length, c.game.moveLog.length);
  });

  test('resume never calls newGame: a bad save falls back to a fresh game',
      () async {
    final queue = _queue();
    final a = _Rig(queue: queue, seed: 4);
    a.runDecisions(4);
    final good = await _stored(queue, a.game.save!.id);
    final json = jsonDecode(SaveCodec.encode(good)) as Map<String, Object?>;
    json['check'] = '0000000000000000';
    final bad = SaveCodec.decode(jsonEncode(json)).save!;

    final b = _Rig(queue: queue, seed: 4, resumeFrom: bad);
    expect(b.game.save, isNull);
    expect(b.game.moveLog, isEmpty);
    expect(b.game.resume(bad), isFalse);
    expect(b.game.moveLog, isEmpty);
    expect(b.game.resume(good), isTrue);
    expect(b.game.moveLog.length, 4);
  });

  test('a banked mid-spend save resumes straight into the move tray', () async {
    final queue = _queue();
    final a = _Rig(
      setup: MatchSetup.hotSeat(rules: _banked),
      queue: queue,
      seed: 0,
    );
    a.runUntil(
      () =>
          a.game.phase == GamePhase.awaitingMove &&
          a.game.moveLog.isNotEmpty &&
          a.game.state.bank.isNotEmpty,
    );
    final saved = await _stored(queue, a.game.save!.id);
    expect(a.game.state.awaitingMove, isTrue);

    final b = _Rig(queue: queue, resumeFrom: saved);
    expect(b.game.state, a.game.state);
    expect(b.game.phase, GamePhase.awaitingMove);
    expect(b.game.choice, isNotNull);
    expect(b.game.legal, isNotEmpty);
    expect(b.game.legal.length, a.game.legal.length);
    expect(b.game.state.bank, a.game.state.bank);
    expect(b.game.save!.id, saved.id);

    final logged = b.game.moveLog.length;
    b.runDecisions(logged + 1);
    expect((await _stored(queue, saved.id)).moves, logged + 1);
  });

  test('a banked game resumes at any decision and matches the original',
      () async {
    final queue = _queue();
    final setup = MatchSetup.hotSeat(rules: _banked);
    final a = _Rig(setup: setup, queue: queue, seed: 2);
    for (var n = 1; n <= 12; n++) {
      a.runDecisions(n);
      final saved = await _stored(queue, a.game.save!.id);
      final b = _Rig(queue: _queue(), resumeFrom: saved);
      expect(b.game.state, a.game.state, reason: 'decision $n');
      expect(
        b.game.phase,
        a.game.state.awaitingMove
            ? GamePhase.awaitingMove
            : GamePhase.awaitingRoll,
        reason: 'decision $n',
      );
    }
  });

  test('teammate control: a finished player rolling for the partner resumes',
      () async {
    final queue = _queue();
    final a = _Rig(
      setup: MatchSetup.hotSeat(teams: true),
      queue: queue,
      seed: 0,
    );
    a.runUntil(
      () =>
          a.game.phase == GamePhase.awaitingRoll &&
          a.game.state.controlledSeat != a.game.state.currentSeat,
      maxSteps: 60000,
    );
    final roller = a.game.state.currentSeat;
    final saved = await _stored(queue, a.game.save!.id);

    final b = _Rig(queue: queue, resumeFrom: saved);
    expect(b.game.state, a.game.state);
    expect(b.game.state.currentSeat, roller);
    expect(b.game.state.controlledSeat, isNot(roller));
    expect(b.game.phase, GamePhase.awaitingRoll);

    final logged = b.game.moveLog.length;
    b.runDecisions(logged + 4);
    final after = await _stored(queue, saved.id);
    expect(after.moves, logged + 4);
    expect(SaveReplayer.replay(after).ok, isTrue);
    expect(after.log[logged].seat, roller);
  });

  test('AI seats restart through the turn driver with the saved level',
      () async {
    var setup = MatchSetup.hotSeat(players: 2);
    setup = setup
        .withSeat(0, const SeatConfig.ai(level: AiLevel.hard))
        .withSeat(2, const SeatConfig.ai(level: AiLevel.easy));

    final queue = _queue();
    final first = _scriptedDriver(<AiRequest>[]);
    final a = _Rig(setup: setup, queue: queue, seed: 6, aiDriver: first);
    a.game.spec = MotionSpec.reduced;
    for (var i = 0; i < 20000 && a.game.moveLog.length < 6; i++) {
      a.step(16);
    }
    expect(a.game.moveLog.length, greaterThanOrEqualTo(6));
    final saved = await _stored(queue, a.game.save!.id);

    final asked = <AiRequest>[];
    final b = _Rig(
      queue: queue,
      resumeFrom: saved,
      aiDriver: _scriptedDriver(asked),
    );
    b.game.spec = MotionSpec.reduced;
    expect(b.game.setup, setup);
    expect(b.game.moveLog.length, saved.moves);
    for (var i = 0; i < 20000 && b.game.moveLog.length < saved.moves + 4; i++) {
      b.step(16);
    }
    expect(b.game.moveLog.length, greaterThanOrEqualTo(saved.moves + 4));
    expect(asked, isNotEmpty);
    for (final request in asked) {
      expect(
        request.level,
        request.state.currentSeat == 0 ? AiLevel.hard : AiLevel.easy,
      );
    }
    expect((await _stored(queue, saved.id)).moves, b.game.moveLog.length);
  });

  test('a failing store raises one quiet notice and never stops play',
      () async {
    final queue = _queue(_FailingStore());
    final rig = _Rig(queue: queue, seed: 3);
    rig.runDecisions(1);
    await queue.flush();
    await Future<void>.delayed(Duration.zero);
    bool notice() => rig.game.toasts.any((t) => t?.text == 'Not saved');
    expect(notice(), isTrue);

    rig.game.toasts.fillRange(0, seatCount, null);
    rig.runDecisions(4);
    await queue.flush();
    await Future<void>.delayed(Duration.zero);
    expect(notice(), isFalse);
    expect(rig.game.moveLog.length, 4);
  });

  test('without a store nothing is saved and play is unchanged', () {
    var t = 0.0;
    final game = GameController(seed: 3, now: () => t, haptics: false);
    game.roll();
    t = 1500;
    game.tick();
    expect(game.save, isNull);
  });
}

/// An AI backend that answers at once with the first option, recording what
/// it was asked.
AiTurnDriver _scriptedDriver(List<AiRequest> asked) => AiTurnDriver(
      backend: (sink) => _Instant(sink, asked.add),
    );

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
