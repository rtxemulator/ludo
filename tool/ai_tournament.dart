/// Self-play tournaments and a speed benchmark for the Milestone 4 AI.
///
///   dart run tool/ai_tournament.dart --a hard:8000 --b easy --games 400
///   dart run tool/ai_tournament.dart --suite --games 400 --jobs 6
///   dart run tool/ai_tournament.dart --bench
///
/// Options: `--layout duel|one-vs-three|teams`, `--preset classic|quick|
/// strategic|banked|banked-strategic|blockade-options`, `--games N`,
/// `--jobs N`, `--seed N`, `--weights v1,...,v10`, `--full-ranking`.
/// Specs: `random`, `easy`, `medium[:nodes]`, `hard[:nodes]`, `expert[:nodes]`.
library;

import 'dart:io';
import 'dart:math';

import 'package:ludo/ai/ai.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';

import 'tournament.dart';

/// Node budgets the suite and the default tiers use in tournaments.
const Map<String, int> suiteNodes = {
  'medium': 400,
  'hard': 2500,
  'expert': 8000,
};

Future<void> main(List<String> argv) async {
  final opts = <String, String>{};
  final flags = <String>{};
  for (var i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith('--')) {
      continue;
    }
    final key = argv[i].substring(2);
    if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
      opts[key] = argv[++i];
    } else {
      flags.add(key);
    }
  }
  final games = int.parse(opts['games'] ?? '200');
  final jobs = int.parse(opts['jobs'] ?? '${Platform.numberOfProcessors}');
  final seed = int.parse(opts['seed'] ?? '1000');
  final weights = opts['weights']?.split(',').map(double.parse).toList();
  final preset = opts['preset'] ?? 'classic';
  final rules =
      rulesByName(preset, fullRanking: flags.contains('full-ranking'));

  if (flags.contains('bench')) {
    _bench(rules);
    return;
  }

  Layout layout(String name) => switch (name) {
        'duel' => Layout.duel,
        'one-vs-three' => Layout.oneVsThree,
        'teams' => Layout.teams,
        _ => throw ArgumentError.value(name, 'layout'),
      };

  Future<void> row(String a, String b, Layout l) async {
    final sw = Stopwatch()..start();
    final t = await runMatch(
      a: PlayerSpec.parse(a, weights: weights),
      b: PlayerSpec.parse(b, weights: weights),
      layout: l,
      rules: rules,
      games: games,
      baseSeed: seed,
      jobs: jobs,
    );
    final (lo, hi) = t.interval;
    stdout.writeln('| ${l.name} | $preset | $a | $b | ${t.games} | ${t.wins} '
        '| ${(t.rate * 100).toStringAsFixed(1)}% '
        '| ${(lo * 100).toStringAsFixed(1)}-${(hi * 100).toStringAsFixed(1)}% '
        '| ${sw.elapsed.inSeconds}s${t.unfinished > 0 ? ' (${t.unfinished} unfinished)' : ''} |');
  }

  stdout.writeln('| layout | preset | A | B | games | A wins | win rate '
      '| 95% CI | time |');
  stdout.writeln('|---|---|---|---|---|---|---|---|---|');
  if (flags.contains('suite')) {
    String s(String level) => '$level:${suiteNodes[level]}';
    final l = layout(opts['layout'] ?? 'duel');
    for (final (a, b) in [
      ('easy', 'random'),
      (s('medium'), 'random'),
      (s('expert'), 'random'),
      (s('medium'), 'easy'),
      (s('hard'), s('medium')),
      (s('expert'), s('hard')),
    ]) {
      await row(a, b, l);
    }
  } else {
    await row(
      opts['a'] ?? 'hard',
      opts['b'] ?? 'easy',
      layout(opts['layout'] ?? 'duel'),
    );
  }
}

/// Decisions per second of the engine and of each tier on sampled positions.
void _bench(RulesConfig rules) {
  final rng = Random(5);
  final states = <GameState>[];
  var state = Engine.newGame(seed: 77, rules: rules);
  var guard = 0;
  while (!state.isOver && guard++ < 3000) {
    if (!state.awaitingMove) {
      state = Engine.roll(state).state;
      continue;
    }
    final legal = Engine.legalMoves(state);
    if (legal.length > 1 && rng.nextInt(4) == 0) {
      states.add(state);
    }
    state = Engine.apply(state, legal[rng.nextInt(legal.length)]);
  }
  stdout.writeln('${states.length} sample positions, preset $rules');

  final sw = Stopwatch()..start();
  var applies = 0;
  for (final s in states) {
    for (final m in Engine.legalMoves(s)) {
      Engine.apply(s, m);
      applies++;
    }
  }
  stdout
      .writeln('apply: ${(applies / sw.elapsedMilliseconds * 1000).round()}/s');
  sw
    ..reset()
    ..start();
  applies = 0;
  for (final s in states) {
    for (final m in Engine.legalMoves(s)) {
      Engine.applyLegal(s, m);
      applies++;
    }
  }
  stdout.writeln(
      'applyLegal: ${(applies / sw.elapsedMilliseconds * 1000).round()}/s');

  for (final level in [AiLevel.medium, AiLevel.hard, AiLevel.expert]) {
    final player = AiPlayer.nodes(level, 50000);
    final times = <int>[];
    var nodes = 0;
    var depth = 0;
    for (final s in states.take(60)) {
      final w = Stopwatch()..start();
      player.choose(s, Engine.legalMoves(s));
      times.add(w.elapsedMicroseconds);
      nodes += player.lastNodes;
      depth += player.lastDepth;
    }
    times.sort();
    final total = times.fold(0, (a, b) => a + b);
    stdout.writeln('${level.name} (cap 50k nodes): '
        'avg ${(total / times.length / 1000).toStringAsFixed(1)} ms, '
        'p95 ${(times[(times.length * 0.95).floor()] / 1000).toStringAsFixed(1)} ms, '
        'nodes/s ${(nodes / total * 1e6).round()}, '
        'avg depth ${(depth / times.length).toStringAsFixed(2)}');
  }
}
