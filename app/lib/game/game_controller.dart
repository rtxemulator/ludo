import 'package:flutter/foundation.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/haptics.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/dice3d.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/move_plan.dart';
import 'package:ludo/ui/core/pt.dart';

import '../haptics/haptics_service.dart';

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

  /// Seat on turn: the one whose dock holds the live die (and whose yard
  /// glows). While a roll runs it is the roller.
  int diceSeat = 0;

  /// Seat that rolled the die in [dice] (differs from [diceSeat] once the
  /// turn has passed but the reveal is still playing).
  int rollerSeat = 0;

  /// Seat that was on turn before the last change, and when it changed
  /// (frame-clock ms). Drives the 200 ms ghost <-> live handoff of the docks.
  int? prevActiveSeat;
  double activeSinceMs = -1e9;

  /// Short hint such as "No legal move"; cleared on the next roll. Shown by
  /// the dock toasts (step P5).
  String? message;

  /// The roll that is tumbling, or the last one (the painter keeps sampling
  /// it through the reveal after the result was applied).
  Dice3dTimeline? dice;
  double diceStartMs = 0;

  /// Last roll of every seat (its ghost die); cleared on a new game.
  final List<Dice3dTimeline?> seatDice = List.filled(seatCount, null);

  /// Frame-clock time of the last out-of-turn tap on each dock.
  final List<double> dockPulseMs = List.filled(seatCount, -1e9);

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
  bool _diceImpactFired = false;
  int _rollCount = 0;

  /// Seat whose turn it is (lights its yard); `null` once the game is over.
  int? get activeSeat => phase == GamePhase.gameOver ? null : diceSeat;

  /// Whether the frame ticker should be running.
  ///
  /// It runs whenever a turn is on: the active yard breathes and the pending
  /// die idles even while nobody is moving anything.
  bool get needsTicker => phase != GamePhase.gameOver;

  /// Starts a fresh match (random seed unless [seed] is given).
  void newGame({int? seed}) {
    final s = seed ?? (DateTime.now().microsecondsSinceEpoch & 0x7fffffff);
    state = Engine.newGame(seed: s, rules: rules);
    phase = GamePhase.awaitingRoll;
    legal = const [];
    lastRoll = null;
    message = null;
    dice = null;
    seatDice.fillRange(0, seatCount, null);
    dockPulseMs.fillRange(0, seatCount, -1e9);
    plan = null;
    _pendingRoll = null;
    _after = null;
    diceSeat = state.currentSeat;
    prevActiveSeat = null;
    activeSinceMs = -1e9;
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
    rollerSeat = diceSeat;
    // Visual-only seed: never the game's dice PRNG.
    _rollCount++;
    final seed = (state.turnNumber * 1000003 + _rollCount * 7919) & 0x7fffffff;
    final timeline = Dice3dTimeline(
      value: result.value,
      seed: seed,
      spec: spec,
    );
    dice = timeline;
    diceStartMs = _now();
    _diceImpactFired = false;
    message = null;
    phase = GamePhase.rolling;
    notifyListeners();
  }

  /// Quick-roll: skips a running roll to its settle (the result is the same,
  /// it only arrives sooner). Ignored outside a roll.
  void quickRoll() {
    if (phase != GamePhase.rolling) {
      return;
    }
    // The skipped bounces are not felt either; only the settle click plays.
    _diceImpactFired = true;
    diceStartMs = _now() - dice!.settleMs;
    tick();
  }

  /// A tap on seat [seat]'s dock: rolls (or quick-rolls) when it is that
  /// seat's turn, otherwise only flashes the dock.
  void dockTap(int seat) {
    if (seat == activeSeat) {
      if (phase == GamePhase.awaitingRoll) {
        roll();
        return;
      }
      if (phase == GamePhase.rolling) {
        quickRoll();
        return;
      }
    }
    pulseDock(seat);
  }

  /// Flashes [seat]'s dock (a tap that did nothing).
  void pulseDock(int seat) {
    dockPulseMs[seat] = _now();
  }

  /// Makes [seat] the one on turn, starting the dock handoff.
  void _activate(int seat) {
    if (seat == diceSeat) {
      return;
    }
    prevActiveSeat = diceSeat;
    diceSeat = seat;
    activeSinceMs = _now();
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
      final t = now - diceStartMs;
      final impacts = dice!.impactsMs;
      if (!_diceImpactFired && impacts.isNotEmpty && t >= impacts.first) {
        // One call spans the three bounces (the pattern has the gaps).
        _diceImpactFired = true;
        feedback.play(HapticEvent.diceImpact);
      }
      // The face locks at the settle; the reveal ring plays on afterwards.
      if (t >= dice!.settleMs) {
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
    seatDice[rollerSeat] = dice;
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
      _activate(state.currentSeat);
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
    _activate(state.currentSeat);
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
