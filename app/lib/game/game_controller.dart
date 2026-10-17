import 'package:flutter/foundation.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/haptics.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/dice_timeline.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/move_plan.dart';
import 'package:ludo/ui/core/pt.dart';

import '../haptics/haptics_service.dart';
import '../ui/theme/palette.dart';

/// Where the hot-seat game currently is.
enum GamePhase { awaitingRoll, rolling, awaitingMove, moving, gameOver }

/// Hot-seat game flow on top of the engine.
///
/// The engine owns all rules and state; this class only sequences
/// `roll -> choose -> apply` and exposes timing for the painters. The UI
/// never mutates [state] directly.
class GameController extends ChangeNotifier {
  GameController({
    this.rules = const RulesConfig(),
    int? seed,
    double Function()? now,
    bool haptics = true,
    HapticsService? hapticsService,
  })  : _now = now ?? _stopwatchClock(),
        feedback = hapticsService ?? HapticsService() {
    feedback.enabled = haptics;
    newGame(seed: seed);
  }

  static double Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds / 1000.0;
  }

  static const BoardGeometry _geo = BoardGeometry();

  final RulesConfig rules;
  final double Function() _now;

  /// Haptic feedback (native channel); `feedback.enabled` is the global
  /// toggle.
  final HapticsService feedback;

  /// Animation timings; set to [MotionSpec.reduced] for reduced motion.
  MotionSpec spec = MotionSpec.standard;

  /// Frame clock (ms). Painters listen to this, widgets listen to `this`.
  final ValueNotifier<double> clock = ValueNotifier<double>(0);

  late GameState state;
  GamePhase phase = GamePhase.awaitingRoll;

  /// Legal moves while [phase] is [GamePhase.awaitingMove].
  List<Move> legal = const [];

  /// Last rolled face (`null` before the first roll).
  int? lastRoll;

  /// Seat whose colour the dice shows.
  int diceSeat = 0;

  /// Short hint such as "No legal move"; cleared on the next roll.
  String? message;

  DiceTimeline? dice;
  double diceStartMs = 0;

  MoveAnimationPlan? plan;
  double planStartMs = 0;

  /// Scale the animated token keeps while hopping (stacking at its target).
  double moverBaseScale = 1;

  /// Cached resting layout of [state] (recomputed when the state changes).
  late List<List<Pt>> resting;
  late List<List<double>> restScales;

  RollResult? _pendingRoll;
  GameState? _after;
  bool _impactFired = false;

  /// Whether the frame ticker should be running.
  bool get needsTicker =>
      phase == GamePhase.rolling ||
      phase == GamePhase.moving ||
      phase == GamePhase.awaitingMove;

  /// One-line status for the top bar.
  String get statusText {
    switch (phase) {
      case GamePhase.awaitingRoll:
        return '${seatNames[state.currentSeat]}: tap the dice';
      case GamePhase.rolling:
        return '${seatNames[diceSeat]} is rolling...';
      case GamePhase.awaitingMove:
        return '${seatNames[diceSeat]}: pick a token';
      case GamePhase.moving:
        return '${seatNames[diceSeat]} moves';
      case GamePhase.gameOver:
        final ranking = state.ranking;
        if (ranking.isEmpty || ranking.first.isEmpty) {
          return 'Game over';
        }
        final names = ranking.first.map((s) => seatNames[s]).join(' & ');
        return '$names win${ranking.first.length == 1 ? 's' : ''}!';
    }
  }

  /// Starts a fresh match (random seed unless [seed] is given).
  void newGame({int? seed}) {
    final s = seed ?? (DateTime.now().microsecondsSinceEpoch & 0x7fffffff);
    state = Engine.newGame(seed: s, rules: rules);
    phase = GamePhase.awaitingRoll;
    legal = const [];
    lastRoll = null;
    message = null;
    dice = null;
    plan = null;
    _pendingRoll = null;
    _after = null;
    diceSeat = state.currentSeat;
    _refreshLayout();
    notifyListeners();
  }

  void _refreshLayout() {
    resting = _geo.restingPoints(state);
    restScales = _geo.restingScales(state);
  }

  /// Rolls the die for the current seat.
  void roll() {
    if (phase != GamePhase.awaitingRoll) {
      return;
    }
    final result = Engine.roll(state);
    _pendingRoll = result;
    diceSeat = state.currentSeat;
    dice = DiceTimeline(value: result.value, spec: spec);
    diceStartMs = _now();
    message = null;
    phase = GamePhase.rolling;
    notifyListeners();
  }

  /// Handles a tap at board position [grid] (in cells). Returns whether a
  /// token was chosen.
  bool tapAt(Pt grid) {
    if (phase != GamePhase.awaitingMove) {
      return false;
    }
    Move? best;
    var bestDistance = 0.8;
    for (final move in legal) {
      final d = resting[move.owner][move.tokenIndex].distanceTo(grid);
      if (d <= bestDistance) {
        bestDistance = d;
        best = move;
      }
    }
    if (best == null) {
      return false;
    }
    _startMove(best);
    return true;
  }

  /// Advances time-based transitions; called every frame by the screen.
  void tick() {
    final now = _now();
    clock.value = now;
    if (phase == GamePhase.rolling) {
      if (now - diceStartMs >= dice!.durationMs) {
        _finishRoll();
      }
    } else if (phase == GamePhase.moving) {
      final t = now - planStartMs;
      if (!_impactFired && t >= plan!.mover.impactMs) {
        _impactFired = true;
        feedback.play(
          plan!.victims.isNotEmpty
              ? HapticEvent.capture
              : plan!.ring != null
                  ? HapticEvent.home
                  : HapticEvent.tokenLand,
        );
      }
      if (t >= plan!.totalMs) {
        _finishMove();
      }
    }
  }

  void _finishRoll() {
    final result = _pendingRoll!;
    _pendingRoll = null;
    state = result.state;
    lastRoll = result.value;
    _refreshLayout();
    feedback.play(HapticEvent.diceSettle);
    if (result.value == 6) {
      feedback.play(HapticEvent.six);
    }
    if (result.outcome == RollOutcome.awaitingMove) {
      legal = Engine.legalMoves(state);
      if (legal.length == 1) {
        _startMove(legal.first);
        return;
      }
      phase = GamePhase.awaitingMove;
    } else {
      message = result.outcome == RollOutcome.tripleSixForfeit
          ? 'Three sixes: turn forfeited'
          : 'No legal move';
      diceSeat = state.currentSeat;
      phase = GamePhase.awaitingRoll;
    }
    notifyListeners();
  }

  void _startMove(Move move) {
    final before = state;
    final after = Engine.apply(before, move);
    final newPlan = MoveAnimationPlan.plan(
      before: before,
      after: after,
      move: move,
      spec: spec,
    );
    final reachedHome =
        after.tokens[move.owner][move.tokenIndex] == finishPosition;
    moverBaseScale = reachedHome
        ? 1
        : _geo.restingScales(after)[move.owner][move.tokenIndex];
    plan = newPlan;
    _after = after;
    planStartMs = _now();
    _impactFired = false;
    legal = const [];
    phase = GamePhase.moving;
    notifyListeners();
  }

  void _finishMove() {
    state = _after!;
    _after = null;
    plan = null;
    _refreshLayout();
    legal = const [];
    diceSeat = state.currentSeat;
    phase = state.isOver ? GamePhase.gameOver : GamePhase.awaitingRoll;
    if (phase == GamePhase.gameOver) {
      feedback.play(HapticEvent.win);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    clock.dispose();
    feedback.dispose();
    super.dispose();
  }
}
