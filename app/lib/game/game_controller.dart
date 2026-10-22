import 'package:flutter/foundation.dart';
import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/haptics.dart';
import 'package:ludo/ui/core/bank_choice.dart';
import 'package:ludo/ui/core/bank_tray.dart';
import 'package:ludo/ui/core/board_geometry.dart';
import 'package:ludo/ui/core/dice3d.dart';
import 'package:ludo/ui/core/frame_stats.dart';
import 'package:ludo/ui/core/fx.dart';
import 'package:ludo/ui/core/fx_scene.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/move_plan.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/ui/core/revert_plan.dart';

import '../haptics/haptics_service.dart';

/// Where the hot-seat game currently is.
enum GamePhase { awaitingRoll, rolling, awaitingMove, moving, gameOver }

/// A short notice at a seat's dock ("No move"); the overlay paints it facing
/// that seat.
class DockToast {
  const DockToast(this.text, this.startMs);

  final String text;
  final double startMs;
}

/// Game flow on top of the engine, for the seats of a [MatchSetup].
///
/// The engine owns all rules and state; this class only sequences
/// `roll -> choose -> apply` and exposes timing for the painters. The UI
/// never mutates [state] directly. Human seats act through taps; AI seats
/// are driven from [tick] with a short think time so their rolls and moves
/// stay readable.
class GameController extends ChangeNotifier {
  GameController({
    RulesConfig rules = const RulesConfig(),
    MatchSetup? setup,
    int? seed,
    double Function()? now,
    bool haptics = true,
    HapticsService? hapticsService,
  })  : _setup = setup ?? MatchSetup.hotSeat(rules: rules),
        _now = now ?? _stopwatchClock(),
        feedback = hapticsService ?? HapticsService() {
    feedback.enabled = haptics;
    newGame(seed: seed);
  }

  static double Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds / 1000.0;
  }

  static const BoardGeometry _geo = BoardGeometry();

  MatchSetup _setup;
  final double Function() _now;
  static const GreedyBot _bot = GreedyBot();

  /// Who sits where and who controls each seat.
  MatchSetup get setup => _setup;

  /// The rules of the running match.
  RulesConfig get rules => _setup.rules;

  /// Whether banked ("stacking") dice rolls are on. Everything banked-only
  /// (roll tray, selection, revert) is inert when this is `false`.
  bool get banked => _setup.rules.bankedRolls;

  /// Switches banked rolls on or off; a change starts a new game.
  void setBankedRolls(bool on) {
    if (_setup.rules.bankedRolls == on) {
      return;
    }
    _setup = _setup.withRules(_setup.baseRules.copyWith(bankedRolls: on));
    newGame();
  }

  /// Whether [seat] is played by the computer.
  bool isAi(int seat) => _setup.typeOf(seat) == SeatType.ai;

  /// Whether the computer is the one to roll or choose now.
  bool get aiTurn =>
      (phase == GamePhase.awaitingRoll || phase == GamePhase.awaitingMove) &&
      isAi(state.currentSeat);

  /// Think time before an AI seat rolls, and before it picks a move (ms).
  static const double aiRollDelayMs = 700;
  static const double aiMoveDelayMs = 650;

  /// Reduced motion shortens the think time.
  static const double aiReducedDelayMs = 250;

  /// When the AI acts next (frame-clock ms); `null` while nothing is due.
  double? _aiDueMs;

  /// Haptic feedback (native channel); `feedback.enabled` is the global
  /// toggle.
  final HapticsService feedback;

  MotionSpec _spec = MotionSpec.standard;

  /// Animation timings; set to [MotionSpec.reduced] for reduced motion.
  MotionSpec get spec => _spec;
  set spec(MotionSpec value) {
    _spec = value;
    tray.spec = value;
  }

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

  /// Short hint such as "No move"; cleared on the next roll. Painted by the
  /// dock toasts.
  String? message;

  /// Toast per seat (shown for [MotionSpec.toastMs] from its start).
  final List<DockToast?> toasts = List.filled(seatCount, null);

  /// Rings, sparks, pocket glows and tap nudges that are alive now. They
  /// outlive the move plan that spawned them.
  final FxScene fx = FxScene();

  /// Seat whose roll had no legal move and when: its tokens dim and its die
  /// shakes (frame-clock ms).
  int? noMoveSeat;
  double noMoveMs = -1e9;

  /// Win confetti and when the game ended (frame-clock ms).
  ConfettiBurst? confetti;
  double gameOverMs = -1e9;
  bool _tickerStopNotified = false;

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

  /// Banked rolls: the chips of the roll trays (view state; the dice
  /// themselves are `state.bank`).
  final BankTray tray = BankTray();

  /// Banked rolls: what can be spent right now and which chip is selected
  /// (only in the moving phase, `null` otherwise).
  BankChoice? choice;

  /// Banked rolls: tokens gliding back after a dead end, and when that
  /// started (frame-clock ms; may lie slightly ahead while the last chip is
  /// shown).
  RevertAnimation? revert;
  double revertStartMs = 0;

  /// Banked rolls: when a tap on the live die was refused because the bank
  /// has to be spent first (the die and the tray shake).
  double bankShakeMs = -1e9;

  /// Scale the animated token keeps while hopping (stacking at its target).
  double moverBaseScale = 1;

  /// Cached resting layout of [state] (recomputed when the state changes).
  late List<List<Pt>> resting;
  late List<List<double>> restScales;

  RollResult? _pendingRoll;
  GameState? _rollBefore;
  Move? _autoMove;
  double _autoMoveAtMs = 0;
  GameState? _after;
  bool _impactFired = false;
  bool _diceImpactFired = false;
  int _rollCount = 0;

  /// Seat whose turn it is (lights its yard); `null` once the game is over.
  int? get activeSeat => phase == GamePhase.gameOver ? null : diceSeat;

  /// Whether the frame ticker should be running.
  ///
  /// It runs whenever a turn is on (the active yard breathes and the pending
  /// die idles even while nobody is moving anything) and while the win
  /// confetti flies.
  bool get needsTicker => phase != GamePhase.gameOver || _celebrating;

  bool get _celebrating =>
      !spec.reducedMotion && _now() - gameOverMs < spec.confettiMs;

  /// Starts a fresh match (random seed unless [seed] is given).
  void newGame({int? seed}) {
    final s = seed ?? (DateTime.now().microsecondsSinceEpoch & 0x7fffffff);
    state = _setup.newGame(s);
    _aiDueMs = null;
    _clearVariants();
    phase = GamePhase.awaitingRoll;
    legal = const [];
    lastRoll = null;
    message = null;
    dice = null;
    seatDice.fillRange(0, seatCount, null);
    dockPulseMs.fillRange(0, seatCount, -1e9);
    toasts.fillRange(0, seatCount, null);
    fx.clear();
    noMoveSeat = null;
    noMoveMs = -1e9;
    confetti = null;
    gameOverMs = -1e9;
    _tickerStopNotified = false;
    plan = null;
    tray.clear();
    choice = null;
    revert = null;
    bankShakeMs = -1e9;
    _autoMove = null;
    _rollBefore = null;
    _pendingRoll = null;
    _after = null;
    diceSeat = state.currentSeat;
    prevActiveSeat = null;
    activeSinceMs = -1e9;
    _refreshLayout();
    notifyListeners();
  }

  /// Test hook: puts the table in [loaded] (a state with a pending die or,
  /// with banked rolls, in the moving phase) as if it had been rolled.
  @visibleForTesting
  void debugLoad(GameState loaded) {
    state = loaded;
    diceSeat = loaded.currentSeat;
    rollerSeat = diceSeat;
    _clearVariants();
    _refreshLayout();
    if (loaded.awaitingMove) {
      if (banked) {
        _enterMoving();
      } else {
        legal = Engine.legalMoves(loaded);
        phase = GamePhase.awaitingMove;
      }
    } else {
      legal = const [];
      phase = GamePhase.awaitingRoll;
    }
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
    _rollBefore = state;
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
        if (aiTurn) {
          // The computer rolls by itself.
          pulseDock(seat);
        } else {
          roll();
        }
        return;
      }
      if (phase == GamePhase.rolling) {
        quickRoll();
        return;
      }
      if (banked && phase == GamePhase.awaitingMove && !aiTurn) {
        // The live die is the roll button, but the bank has to be spent
        // first: it shakes, and so does the tray.
        final now = _now();
        bankShakeMs = now;
        tray.shake(state.currentSeat, now);
        feedback.play(HapticEvent.illegal);
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
  ///
  /// While a roll is due the tap only flashes the dock of the seat on turn;
  /// while a token is to be chosen, a tap on a token that cannot move nudges
  /// it (with a faint red ring and a double tick).
  bool tapAt(Pt grid) {
    if (aiTurn) {
      return false;
    }
    if (phase == GamePhase.awaitingRoll) {
      pulseDock(diceSeat);
      return false;
    }
    if (phase != GamePhase.awaitingMove) {
      return false;
    }
    if (variants.isNotEmpty) {
      final picked = _pickVariant(grid);
      _clearVariants();
      if (picked != null) {
        _startMove(picked);
        return true;
      }
      notifyListeners();
    }
    if (banked) {
      return _tapBanked(grid);
    }
    final token = _nearestToken(legal, grid);
    if (token == null) {
      _illegalTap(grid);
      return false;
    }
    final mine = [
      for (final m in legal)
        if (m.owner == token.$1 && m.moves(token.$2)) m,
    ];
    if (mine.length == 1) {
      _startMove(mine.single);
      return true;
    }
    _promptVariants(mine);
    return false;
  }

  /// The token (owner, index) of [moves] nearest to [grid], within reach of a
  /// tap; both tokens of a moving blockade count.
  (int, int)? _nearestToken(Iterable<Move> moves, Pt grid) {
    (int, int)? best;
    var bestDistance = 0.8;
    for (final move in moves) {
      for (final index in [
        move.tokenIndex,
        if (move.isUnit) move.partnerIndex,
      ]) {
        final d = resting[move.owner][index].distanceTo(grid);
        if (d <= bestDistance) {
          bestDistance = d;
          best = (move.owner, index);
        }
      }
    }
    return best;
  }

  /// Moves a tapped token (or blockade) could make: when it is more than
  /// one, the destinations are shown as markers and the next tap on one of
  /// them chooses. Empty when no choice is pending.
  List<Move> variants = const [];

  /// Where each of [variants] ends (board grid points, same order).
  List<Pt> variantPoints = const [];

  void _promptVariants(List<Move> moves) {
    variants = moves;
    variantPoints = [
      for (final m in moves)
        _geo.restingPoints(Engine.apply(state, m))[m.owner][m.tokenIndex],
    ];
    feedback.play(HapticEvent.select);
    notifyListeners();
  }

  void _clearVariants() {
    variants = const [];
    variantPoints = const [];
  }

  Move? _pickVariant(Pt grid) {
    Move? best;
    var bestDistance = 0.9;
    for (var k = 0; k < variants.length; k++) {
      final d = variantPoints[k].distanceTo(grid);
      if (d <= bestDistance) {
        bestDistance = d;
        best = variants[k];
      }
    }
    return best;
  }

  /// Banked rolls: a tap on the board while dice are to be spent. A token
  /// with one option spends it, the selected chip decides otherwise, and a
  /// token with several options prompts a choice from the tray.
  bool _tapBanked(Pt grid) {
    final c = choice;
    if (c == null) {
      return false;
    }
    final token = _nearestToken(c.legal, grid);
    if (token == null) {
      _illegalTap(grid);
      return false;
    }
    final result = c.tapToken(token.$1, token.$2);
    switch (result.kind) {
      case TokenTapKind.variants:
        _promptVariants(result.moves!);
        return false;
      case TokenTapKind.spend:
        _startMove(result.move!);
        return true;
      case TokenTapKind.select:
        _syncSelection();
        feedback.play(HapticEvent.select);
        notifyListeners();
        return false;
      case TokenTapKind.prompt:
        tray.prompt(state.currentSeat, _now());
        feedback.play(HapticEvent.noMove);
        return false;
      case TokenTapKind.none:
        _illegalTap(grid);
        return false;
    }
  }

  /// Banked rolls: a tap on chip [chip] (an index into the bank) of [seat]'s
  /// tray. Selects it when it can be spent now, otherwise the tray shakes.
  void chipTap(int seat, int chip) {
    final c = choice;
    if (!banked ||
        phase != GamePhase.awaitingMove ||
        c == null ||
        aiTurn ||
        seat != state.currentSeat) {
      return;
    }
    if (c.tapChip(chip)) {
      _clearVariants();
      _syncSelection();
      feedback.play(HapticEvent.select);
      notifyListeners();
    } else {
      tray.shake(seat, _now());
      feedback.play(HapticEvent.illegal);
    }
  }

  /// Whether [seat]'s chips take taps now.
  bool trayTappable(int seat) =>
      banked &&
      phase == GamePhase.awaitingMove &&
      choice != null &&
      !aiTurn &&
      seat == state.currentSeat;

  /// Tokens whose glow is drawn: the moves of the selected chip (every legal
  /// move while none is selected), one entry per token.
  List<Move> get glowMoves {
    final source = banked ? choice?.glowMoves ?? const <Move>[] : legal;
    if (!banked && !source.any((m) => m.isUnit)) {
      return legal; // the common case: nothing to expand
    }
    final seen = <int>{};
    final glowing = <Move>[];
    for (final m in source) {
      // Both tokens of a moving blockade glow.
      for (final index in [m.tokenIndex, if (m.isUnit) m.partnerIndex]) {
        if (seen.add(m.owner * tokensPerSeat + index)) {
          glowing.add(
            index == m.tokenIndex
                ? m
                : Move(
                    owner: m.owner,
                    tokenIndex: index,
                    from: m.from,
                    to: m.to,
                    dieIndex: m.dieIndex,
                  ),
          );
        }
      }
    }
    return glowing;
  }

  /// Tells the tray which chip is selected.
  void _syncSelection() {
    tray.select(state.currentSeat, choice?.selected, _now());
  }

  /// Gives each seat's tray the width its layout slot has (chips per row).
  void syncTrayCapacity(List<double> chips) {
    final now = _now();
    for (var seat = 0; seat < chips.length && seat < seatCount; seat++) {
      tray.setCapacity(seat, chips[seat], now);
    }
  }

  /// A tap during a choice that hit a token with no move (an opponent's, or
  /// one of the mover's own that this roll cannot move).
  void _illegalTap(Pt grid) {
    int? seat;
    var index = 0;
    var nearest = 0.8;
    for (final s in state.activeSeats) {
      for (var i = 0; i < tokensPerSeat; i++) {
        final d = resting[s][i].distanceTo(grid);
        if (d <= nearest) {
          nearest = d;
          seat = s;
          index = i;
        }
      }
    }
    if (seat == null) {
      return;
    }
    fx.addNudge(
      FxNudge(seat: seat, index: index, startMs: _now()),
      resting[seat][index],
      spec,
    );
    feedback.play(HapticEvent.illegal);
  }

  /// Advances time-based transitions; called every frame by the screen.
  void tick() {
    final now = _now();
    PaintProbe.nextFrame();
    clock.value = now;
    fx.prune(now, spec);
    tray.prune(now, spec);
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
    } else if (phase == GamePhase.awaitingMove) {
      final auto = _autoMove;
      if (auto != null && now >= _autoMoveAtMs) {
        // A forced spend of the bank: the chip had its moment, now it goes.
        _startMove(auto);
      }
    } else if (phase == GamePhase.moving && revert != null) {
      if (now - revertStartMs >= revert!.totalMs) {
        _finishRevert();
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
                  : plan!.formed
                      ? HapticEvent.select
                      : HapticEvent.tokenLand,
        );
      }
      if (t >= plan!.totalMs) {
        _finishMove();
      }
    } else if (phase == GamePhase.gameOver &&
        !_tickerStopNotified &&
        !needsTicker) {
      // The confetti is over: let the screen stop the ticker.
      _tickerStopNotified = true;
      notifyListeners();
    }
    _driveAi(now);
  }

  /// Lets an AI seat roll and choose: after a short think time it presses the
  /// same buttons a person would, so the animations, haptics and rules flow
  /// are identical for both.
  void _driveAi(double now) {
    if (!aiTurn) {
      _aiDueMs = null;
      return;
    }
    if (phase == GamePhase.awaitingMove && _autoMove != null) {
      // A forced spend of the bank goes by itself.
      return;
    }
    final slow =
        phase == GamePhase.awaitingRoll ? aiRollDelayMs : aiMoveDelayMs;
    final due =
        _aiDueMs ??= now + (spec.reducedMotion ? aiReducedDelayMs : slow);
    if (now < due) {
      return;
    }
    _aiDueMs = null;
    if (phase == GamePhase.awaitingRoll) {
      roll();
    } else if (legal.isNotEmpty) {
      _startMove(_bot.choose(state, legal));
    }
  }

  void _finishRoll() {
    final result = _pendingRoll!;
    _pendingRoll = null;
    final before = _rollBefore ?? state;
    _rollBefore = null;
    if (banked) {
      _finishBankedRoll(before, result);
      return;
    }
    final dimSeat = state.controlledSeat;
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
      final now = _now();
      message = result.outcome == RollOutcome.tripleSixForfeit
          ? 'Three sixes'
          : 'No move';
      toasts[rollerSeat] = DockToast(message!, now);
      noMoveSeat = dimSeat;
      noMoveMs = now;
      feedback.play(HapticEvent.noMove);
      _activate(state.currentSeat);
      phase = GamePhase.awaitingRoll;
    }
    notifyListeners();
  }

  /// Banked rolls: applies the outcome of one roll (the die only joined the
  /// bank, or the sequence ended, or it was wiped or reverted).
  void _finishBankedRoll(GameState before, RollResult result) {
    final now = _now();
    final seat = rollerSeat;
    final dimSeat = before.controlledSeat;
    state = result.state;
    lastRoll = result.value;
    seatDice[seat] = dice;
    _refreshLayout();
    feedback.play(HapticEvent.diceSettle);
    if (result.value == 6) {
      feedback.play(HapticEvent.six);
    }
    switch (result.outcome) {
      case RollOutcome.banked:
        // A 6: the die joins the bank and the same seat rolls again.
        tray.append(seat, result.value, now);
        phase = GamePhase.awaitingRoll;
      case RollOutcome.awaitingMove:
        tray.append(seat, result.value, now);
        _enterMoving();
      case RollOutcome.tripleSixForfeit:
        // The whole bank is wiped; moves already made stay.
        tray.exitAll(seat, ChipExit.wipe, now);
        message = 'Three sixes';
        toasts[seat] = DockToast(message!, now);
        noMoveSeat = dimSeat;
        noMoveMs = now;
        feedback.play(HapticEvent.noMove);
        _activate(state.currentSeat);
        phase = GamePhase.awaitingRoll;
      case RollOutcome.bankDeadEnd:
        // The last die joins the bank for a moment, then the bank goes and
        // the board glides back to where the turn began. `before` is the
        // board with the turn's moves; `state` is already reverted.
        const hold = 260.0;
        final delay = spec.reducedMotion ? 0.0 : hold;
        tray.append(seat, result.value, now);
        tray.exitAll(seat, ChipExit.revert, now, delayMs: delay);
        message = 'Turn undone';
        toasts[seat] = DockToast(message!, now);
        feedback.play(HapticEvent.noMove);
        final anim = RevertAnimation.plan(
          before: before,
          after: state,
          spec: spec,
          startMs: now + delay,
        );
        if (anim.isEmpty) {
          _activate(state.currentSeat);
          phase = GamePhase.awaitingRoll;
        } else {
          fx.addAll(anim.effects);
          revert = anim;
          revertStartMs = now + delay;
          phase = GamePhase.moving;
        }
      case RollOutcome.noLegalMoves:
        // Not produced with banked rolls; pass cleanly if it ever is.
        _activate(state.currentSeat);
        phase = GamePhase.awaitingRoll;
    }
    notifyListeners();
  }

  /// The tokens are back: the next seat may roll.
  void _finishRevert() {
    revert = null;
    _activate(state.currentSeat);
    phase = GamePhase.awaitingRoll;
    notifyListeners();
  }

  /// Banked rolls: the moving phase (or the next spend of it) starts. Picks
  /// the selection (automatic when only one value can be played) and
  /// schedules a forced spend.
  void _enterMoving() {
    final now = _now();
    final seat = state.currentSeat;
    tray.reconcile(seat, state.bank, now);
    final c = BankChoice.of(state);
    choice = c;
    legal = c.legal;
    tray.select(seat, c.selected, now);
    _autoMove = c.forced;
    _autoMoveAtMs = now + (spec.reducedMotion ? 0 : spec.tray.autoSpendMs);
    phase = GamePhase.awaitingMove;
  }

  void _startMove(Move move) {
    final before = state;
    final after = Engine.apply(before, move);
    final start = _now();
    _autoMove = null;
    _clearVariants();
    if (banked) {
      // The chip at the spent die's index flies to the token.
      tray.spendAt(
        before.currentSeat,
        move.dieIndex,
        resting[move.owner][move.tokenIndex],
        start,
      );
      choice = null;
    }
    final newPlan = MoveAnimationPlan.plan(
      before: before,
      after: after,
      move: move,
      spec: spec,
      startMs: start,
    );
    final reachedHome =
        after.tokens[move.owner][move.tokenIndex] == finishPosition;
    moverBaseScale = reachedHome
        ? 1
        : _geo.restingScales(after)[move.owner][move.tokenIndex];
    plan = newPlan;
    fx.addAll(newPlan.effects);
    _after = after;
    planStartMs = start;
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
    if (banked && !state.isOver && state.awaitingMove) {
      // More dice to spend.
      _enterMoving();
      notifyListeners();
      return;
    }
    phase = state.isOver ? GamePhase.gameOver : GamePhase.awaitingRoll;
    if (phase == GamePhase.gameOver) {
      feedback.play(HapticEvent.win);
      gameOverMs = _now();
      _tickerStopNotified = false;
      confetti = ConfettiBurst(
        origin: const Pt(0, 0),
        startMs: gameOverMs,
        seed: state.turnNumber * 31 + 7,
        spec: spec,
      );
    }
    notifyListeners();
  }

  /// Seat of the winning player (or team's first seat); `null` before the end.
  int? get winnerSeat {
    final winners = state.winners;
    return winners == null || winners.isEmpty ? null : winners.first;
  }

  /// Starts the same table again with a fresh seed (the game-over "Rematch").
  void rematch() => newGame();

  @override
  void dispose() {
    clock.dispose();
    feedback.dispose();
    super.dispose();
  }
}
