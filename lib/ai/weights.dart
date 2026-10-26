/// Every tunable number of the evaluation, in "squares of progress" so the
/// scale stays continuous with `GreedyBot`. See `docs/ludo-ai.md` section 3.
///
/// Tuned by self-play (`tool/ai_tournament.dart`); the frozen values and how
/// they were found are in [AiWeights.tuned].
class AiWeights {
  const AiWeights({
    this.safe = 4,
    this.finished = 20,
    this.exposureScale = 1,
    this.exposureBase = 10,
    this.threatScale = 0.5,
    this.threatBase = 25,
    this.blockHold = 3,
    this.blockStuck = 3,
    this.waiting = 6,
    this.bonusRollValue = 8,
    this.out = 10,
  });

  /// Token on a safe square or in the home column.
  final double safe;

  /// Tempo bonus for a finished token (on top of its progress).
  final double finished;

  /// Exposure: `-p_hit * exposureScale * (progress + exposureBase)`.
  final double exposureScale;
  final double exposureBase;

  /// Threat: `+p_hit_by_me * threatScale * (their progress + threatBase)`.
  final double threatScale;
  final double threatBase;

  /// Own wall that has opponents 1-6 squares behind it.
  final double blockHold;

  /// Token 1-6 squares behind an opponent wall.
  final double blockStuck;

  /// Token squatting on a blockade (`GameState.rest > 0`).
  final double waiting;

  /// Banked rolls: flat value of a capture/home bonus roll inside a plan.
  final double bonusRollValue;

  /// Tempo for every token that has left the yard (a token in the yard needs
  /// a 6 or a lucky roll to start; added after the first tournament showed
  /// plain progress undervalues getting out).
  final double out;

  /// Final placement values by rank (best first); the last place is 0.
  static const List<double> placement = [1000, 400, 150, 0];

  /// The weights the tiers play with. Hill-climbing by self-play (44 trials,
  /// `tool/ai_tune.dart`) found nothing above 52.8% against these, so they are
  /// the hand-set starting values (results: docs/ludo-ai.md section 11).
  static const AiWeights tuned = AiWeights();

  static const List<String> names = [
    'safe',
    'finished',
    'exposureScale',
    'exposureBase',
    'threatScale',
    'threatBase',
    'blockHold',
    'blockStuck',
    'waiting',
    'bonusRollValue',
    'out',
  ];

  /// The weights as a vector, in [names] order (for tuning).
  List<double> toVector() => [
        safe,
        finished,
        exposureScale,
        exposureBase,
        threatScale,
        threatBase,
        blockHold,
        blockStuck,
        waiting,
        bonusRollValue,
        out,
      ];

  factory AiWeights.fromVector(List<double> v) {
    if (v.length != names.length) {
      throw ArgumentError.value(v, 'v', 'need ${names.length} values');
    }
    return AiWeights(
      safe: v[0],
      finished: v[1],
      exposureScale: v[2],
      exposureBase: v[3],
      threatScale: v[4],
      threatBase: v[5],
      blockHold: v[6],
      blockStuck: v[7],
      waiting: v[8],
      bonusRollValue: v[9],
      out: v[10],
    );
  }

  @override
  String toString() => 'AiWeights(${[
        for (var i = 0; i < names.length; i++)
          '${names[i]}: ${toVector()[i].toStringAsFixed(2)}'
      ].join(', ')})';
}
