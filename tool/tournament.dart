/// Self-play harness shared by `ai_tournament.dart` and `ai_tune.dart`.
///
/// Games are fully determined by `(seed, rules, seats, player specs)`; every
/// AI uses a node budget (no clock), so a tournament can be re-run bit for
/// bit. Play is split over isolates by game index.
library;

import 'dart:isolate';
import 'dart:math';

import 'package:ludo/ai/ai.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';

/// Who plays a seat: `random`, `easy` (GreedyBot) or `level[:nodes]` with an
/// optional weight vector.
class PlayerSpec {
  const PlayerSpec(this.kind, {this.nodes, this.weights});

  factory PlayerSpec.parse(String text, {List<double>? weights}) {
    final parts = text.split(':');
    return PlayerSpec(
      parts[0],
      nodes: parts.length > 1 ? int.parse(parts[1]) : null,
      weights: weights,
    );
  }

  final String kind;
  final int? nodes;
  final List<double>? weights;

  String get label => nodes == null ? kind : '$kind:$nodes';

  /// A chooser for one game; [rng] feeds `random` only (never the game dice).
  Move Function(GameState, List<Move>) build(Random rng) {
    switch (kind) {
      case 'random':
        return (s, legal) => legal[rng.nextInt(legal.length)];
      case 'easy':
        const bot = GreedyBot();
        return bot.choose;
    }
    final level = AiLevel.values.byName(kind);
    final w =
        weights == null ? AiWeights.tuned : AiWeights.fromVector(weights!);
    final player = nodes == null
        ? AiPlayer(level, weights: w)
        : AiPlayer.nodes(level, nodes!, weights: w);
    return player.choose;
  }
}

/// How a game is laid out.
enum Layout {
  /// Seats 0 and 2: A against B.
  duel,

  /// All four seats, A at a rotating seat against three B.
  oneVsThree,

  /// 2v2 teams (seats 0+2 against 1+3), A is one team.
  teams,
}

/// Rules presets by name (all end on the first finisher unless [fullRanking]).
RulesConfig rulesByName(String name, {bool fullRanking = false}) {
  final base = switch (name) {
    'classic' => const RulesConfig.classic(),
    'quick' => const RulesConfig.quick(),
    'strategic' => const RulesConfig.strategic(),
    'banked' => const RulesConfig(bankedRolls: true),
    'banked-strategic' => const RulesConfig(bankedRolls: true, blockades: true),
    'blockade-options' => const RulesConfig(
        blockades: true,
        blockadeMovement: true,
        blockadeCapture: true,
        pieceOnBlockade: true,
      ),
    _ => throw ArgumentError.value(name, 'preset'),
  };
  return base.copyWith(
    endMode: fullRanking ? EndMode.fullRanking : EndMode.firstToWin,
  );
}

class GameResult {
  const GameResult(this.aWon, this.decisions, this.finished);
  final bool aWon;
  final int decisions;
  final bool finished;
}

/// Plays game number [index] (seed `baseSeed + index ~/ perSeed`, A's seat
/// rotated by `index % perSeed`, so each seed is played with every
/// arrangement).
GameResult playGame({
  required PlayerSpec a,
  required PlayerSpec b,
  required Layout layout,
  required RulesConfig rules,
  required int baseSeed,
  required int index,
  int maxDecisions = 6000,
}) {
  final perSeed = layout == Layout.oneVsThree ? 4 : 2;
  final seed = baseSeed + index ~/ perSeed;
  final turn = index % perSeed;

  late final List<int> seats;
  late final Set<int> aSeats;
  var r = rules;
  switch (layout) {
    case Layout.duel:
      seats = [0, 2];
      aSeats = {turn == 0 ? 0 : 2};
    case Layout.oneVsThree:
      seats = [0, 1, 2, 3];
      aSeats = {turn};
    case Layout.teams:
      seats = [0, 1, 2, 3];
      aSeats = turn == 0 ? {0, 2} : {1, 3};
      r = r.copyWith(teamsEnabled: true);
  }

  final rng = Random(seed * 7919 + 13);
  final chooseA = a.build(rng);
  final chooseB = b.build(rng);
  var state = Engine.newGame(seed: seed, rules: r, activeSeats: seats);
  var decisions = 0;
  while (!state.isOver && decisions < maxDecisions) {
    if (!state.awaitingMove) {
      state = Engine.roll(state).state;
      continue;
    }
    final legal = Engine.legalMoves(state);
    final choose = aSeats.contains(state.currentSeat) ? chooseA : chooseB;
    state = Engine.apply(state, choose(state, legal));
    decisions++;
  }
  if (!state.isOver) {
    return GameResult(false, decisions, false);
  }
  final winner = state.winners!.first;
  return GameResult(aSeats.contains(winner), decisions, true);
}

/// Tally of a run.
class Tally {
  Tally(this.games, this.wins, this.unfinished);
  final int games;
  final int wins;
  final int unfinished;

  double get rate => games == 0 ? 0 : wins / games;

  /// Wilson 95% interval of the win rate.
  (double, double) get interval {
    if (games == 0) {
      return (0, 1);
    }
    const z = 1.96;
    final n = games.toDouble();
    final p = rate;
    final d = 1 + z * z / n;
    final c = p + z * z / (2 * n);
    final m = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n));
    return ((c - m) / d, (c + m) / d);
  }
}

Tally _runChunk(List<Object?> args) {
  final a = args[0] as PlayerSpec;
  final b = args[1] as PlayerSpec;
  final layout = args[2] as Layout;
  final rules = args[3] as RulesConfig;
  final baseSeed = args[4] as int;
  final from = args[5] as int;
  final to = args[6] as int;
  var wins = 0;
  var unfinished = 0;
  for (var i = from; i < to; i++) {
    final g = playGame(
      a: a,
      b: b,
      layout: layout,
      rules: rules,
      baseSeed: baseSeed,
      index: i,
    );
    if (!g.finished) {
      unfinished++;
    } else if (g.aWon) {
      wins++;
    }
  }
  return Tally(to - from, wins, unfinished);
}

/// Plays [games] games of A against B over [jobs] isolates.
Future<Tally> runMatch({
  required PlayerSpec a,
  required PlayerSpec b,
  required Layout layout,
  required RulesConfig rules,
  required int games,
  int baseSeed = 1000,
  int jobs = 1,
}) async {
  // Chunks are multiples of 4 so every seed keeps all its arrangements.
  final chunk = max(4, ((games / jobs / 4).ceil()) * 4);
  final futures = <Future<Tally>>[];
  for (var from = 0; from < games; from += chunk) {
    final args = [
      a,
      b,
      layout,
      rules,
      baseSeed,
      from,
      min(games, from + chunk)
    ];
    futures.add(jobs <= 1
        ? Future.value(_runChunk(args))
        : Isolate.run(() => _runChunk(args)));
  }
  final parts = await Future.wait(futures);
  return Tally(
    parts.fold(0, (s, t) => s + t.games),
    parts.fold(0, (s, t) => s + t.wins),
    parts.fold(0, (s, t) => s + t.unfinished),
  );
}
