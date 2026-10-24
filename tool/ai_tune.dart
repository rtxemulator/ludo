/// Coordinate hill-climb of `AiWeights` by self-play (`docs/ludo-ai.md`
/// section 3).
///
///   dart run tool/ai_tune.dart --sweeps 2 --games 400 --nodes 300 --jobs 6
///
/// Each trial plays a candidate against the current champion (the same
/// search tier and node budget, only the weights differ) on fresh seeds,
/// over a classic and a strategic (blockades) duel with seats swapped. A
/// candidate replaces the champion when its win rate is at least
/// `--accept` (default 0.55). The whole run is deterministic.
library;

import 'dart:io';

import 'package:ludo/ai/ai.dart';

import 'tournament.dart';

Future<void> main(List<String> argv) async {
  final opts = <String, String>{};
  for (var i = 0; i + 1 < argv.length; i += 2) {
    opts[argv[i].substring(2)] = argv[i + 1];
  }
  final sweeps = int.parse(opts['sweeps'] ?? '2');
  final games = int.parse(opts['games'] ?? '400');
  final nodes = int.parse(opts['nodes'] ?? '300');
  final jobs = int.parse(opts['jobs'] ?? '${Platform.numberOfProcessors}');
  final accept = double.parse(opts['accept'] ?? '0.55');
  var factor = double.parse(opts['factor'] ?? '1.6');
  var champion = opts['start'] == null
      ? AiWeights.tuned.toVector()
      : opts['start']!.split(',').map(double.parse).toList();

  var seedCounter = 500000;
  Future<double> duel(List<double> candidate, List<double> champ) async {
    final seed = seedCounter;
    seedCounter += 10000;
    final a = PlayerSpec('medium', nodes: nodes, weights: candidate);
    final b = PlayerSpec('medium', nodes: nodes, weights: champ);
    final classic = await runMatch(
      a: a,
      b: b,
      layout: Layout.duel,
      rules: rulesByName('classic'),
      games: (games * 0.6).round(),
      baseSeed: seed,
      jobs: jobs,
    );
    final strategic = await runMatch(
      a: a,
      b: b,
      layout: Layout.duel,
      rules: rulesByName('strategic'),
      games: (games * 0.4).round(),
      baseSeed: seed + 5000,
      jobs: jobs,
    );
    return (classic.wins + strategic.wins) / (classic.games + strategic.games);
  }

  stdout
      .writeln('start ${champion.map((v) => v.toStringAsFixed(2)).join(',')}');
  for (var sweep = 1; sweep <= sweeps; sweep++) {
    for (var i = 0; i < AiWeights.names.length; i++) {
      double? bestRate;
      List<double>? bestVector;
      for (final up in [true, false]) {
        final v = [...champion];
        v[i] = v[i].abs() < 1e-9
            ? (up ? 1.0 : 0.0)
            : (up ? v[i] * factor : v[i] / factor);
        if (v[i] == champion[i]) {
          continue;
        }
        final rate = await duel(v, champion);
        stdout.writeln('sweep $sweep ${AiWeights.names[i]} '
            '${champion[i].toStringAsFixed(2)} -> ${v[i].toStringAsFixed(2)}: '
            '${(rate * 100).toStringAsFixed(1)}%');
        if (rate >= accept && (bestRate == null || rate > bestRate)) {
          bestRate = rate;
          bestVector = v;
        }
      }
      if (bestVector != null) {
        champion = bestVector;
        stdout.writeln(
            '  accepted: ${champion.map((v) => v.toStringAsFixed(2)).join(',')}');
      }
    }
    factor = 1 + (factor - 1) / 2;
    stdout.writeln('sweep $sweep done: '
        '${champion.map((v) => v.toStringAsFixed(2)).join(',')}');
  }
  stdout
      .writeln('final ${champion.map((v) => v.toStringAsFixed(2)).join(',')}');
}
