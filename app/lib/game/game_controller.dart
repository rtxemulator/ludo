import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ludo/ai/ai.dart';
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
import 'package:ludo/ui/core/move_preview.dart';
import 'package:ludo/ui/core/move_plan.dart';
import 'package:ludo/ui/core/pacing.dart';
import 'package:ludo/ui/core/pt.dart';
import 'package:ludo/seats/seats.dart';
import 'package:ludo/storage/storage.dart';
import 'package:ludo/ui/core/revert_plan.dart';
import 'package:ludo/ui/core/sfx.dart';

import '../audio/audio_service.dart';
import '../audio/game_feedback.dart';
import '../haptics/haptics_service.dart';

/// Where the hot-seat game currently is.
enum GamePhase { awaitingRoll, rolling, awaitingMove, moving, gameOver }

/// A short notice at a seat's dock ("No move"); the overlay paints it facing
/// that seat.
///
/// A [big] toast is the larger kind for a notice that needs a reason:
/// [text] is its title and [detail] a one-line reason under it.
class DockToast {
  const DockToast(this.text, this.startMs, {this.detail, this.big = false});

  /// The one-line reason shown under "Turn undone".
  static const String undoneReason = 'Not every die could be played';

  /// The "Turn undone" notice, big, with its reason.
  const DockToast.undone(this.startMs)
      : text = 'Turn undone',
        detail = undoneReason,
        big = true;

  final String text;
  final double startMs;
  final String? detail;
  final bool big;
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
    AudioService? audio,
    AiTurnDriver? aiDriver,
    SaveWriteQueue? saves,
    DateTime Function()? wallClock,
    GameSave? resumeFrom,
    bool replay = false,
  })  : _setup = setup ?? MatchSetup.hotSeat(rules: rules),
        _replay = replay,
        _now = now ?? _stopwatchClock(),
        _ai = aiDriver ?? AiTurnDriver(),
        _saves = saves,
        _wall = wallClock ?? DateTime.now,
        feedback = GameFeedback(
          haptics: hapticsService ?? HapticsService(),
          audio: audio,
        ) {
    feedback.enabled = haptics;
    if (resumeFrom == null || !resume(resumeFrom)) {
      newGame(seed: seed);
    }
    _saveErrors = _saves?.errors.listen(_onSaveError);
  }

  static double Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds / 1000.0;
  }

  static const BoardGeometry _geo = BoardGeometry();

  MatchSetup _setup;
  final double Function() _now;

  /// A replay presentation model (docs/ludo-saves.md section 11): it shows
  /// states handed to [replayShow] and [replayPlay] and takes no input. No
  /// roll, tap, AI turn or save ever happens in it, and no AI worker starts.
  final bool _replay;

  /// Whether this controller only presents a replay.
  bool get isReplay => _replay;

  // ---- Autosave (docs/ludo-saves.md) --------------------------------------

  final SaveWriteQueue? _saves;
  final DateTime Function() _wall;
  StreamSubscription<Object>? _saveErrors;

  /// The seed the current game was dealt from; kept for the save.
  int _seed = 0;

  /// The decisions made so far (the same list the save holds).
  List<MoveLogEntry> _log = const [];

  /// The save of the current game; `null` until the first decision.
  GameSave? _save;

  /// Set by [debugLoad]: the state no longer derives from the seed and log,
  /// so nothing may be saved.
  bool _autosaveOff = false;
  bool _saveNoticeShown = false;

  /// The seed of the current game.
  int get seed => _seed;

  /// The save of the current game, or `null` before the first decision (or
  /// without a store).
  GameSave? get save => _save;

  /// Decisions logged so far.
  List<MoveLogEntry> get moveLog => _log;

  /// Computes the moves of the Medium, Hard and Expert seats off the UI
  /// isolate (worker, watchdog and baseline-bot fallback live in there).
  final AiTurnDriver _ai;

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

  /// Whether a seat that plays on the worker (Medium, Hard, Expert) sits at
  /// the table; Easy needs no worker.
  bool get _hasSearchingAi => _setup.activeSeats.any(
        (seat) => isAi(seat) && _setup.configOf(seat).aiLevel != AiLevel.easy,
      );

  /// Think time before an AI seat rolls, and before it picks a move: a random
  /// 400..900 ms (`ThinkDelay`; short and fixed with reduced motion).
  final ThinkDelay _think = ThinkDelay();

  /// When the AI acts next (frame-clock ms); `null` while nothing is due.
  double? _aiDueMs;

  /// Haptic feedback (native channel); `feedback.enabled` is the global
  /// toggle.
  final GameFeedback feedback;

  MotionSpec _spec = MotionSpec.standard;

  /// Animation timings; set to [MotionSpec.reduced] for reduced motion.
  MotionSpec get spec => _spec;
  set spec(MotionSpec value) {
    _spec = value;
    tray.spec = value;
  }

  /// The one animation queue (`lib/ui/core/pacing.dart`): hops, captures,
  /// dice and effect tails run one after another, and nothing new (a roll, an
  /// AI action) starts before it is free.
  final AnimationQueue _queue = AnimationQueue();

  /// Time skipped by tapping through a long sequence (ms). Added to the
  /// clock, so every running timeline finishes in the same frame.
  double _skewMs = 0;

  /// The controller's time: the injected clock plus what was skipped.
  double _clock() => _now() + _skewMs;

  /// Whether an animation is running or waiting in the queue.
  bool get animating => _queue.busy(_clock());

  /// Moves a seat with exactly one legal move make by themselves, without a
  /// tap (setting `autoMoveSingle`; off by default). AI seats and the forced
  /// spend of a banked roll always go by themselves.
  bool autoMoveSingle = false;

  /// The move a tap on a token is previewing (destination ring, path trail);
  /// a second tap on that token, or on its ring, plays it. `null` when none.
  MovePreview? preview;

  /// When [preview] opened (frame-clock ms).
  double previewStartMs = 0;

  /// When a turn that had no move passes to the next seat (the roll stays on
  /// the table until then); `null` when no pass is waiting.
  double? _passAtMs;

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

  // How many of the plan's hop sounds have played (one per hop step).
  int _hopsFired = 0;
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
      !spec.reducedMotion && _clock() - gameOverMs < spec.confettiMs;

  /// Starts a fresh match (random seed unless [seed] is given).
  void newGame({int? seed}) {
    final s = seed ?? (DateTime.now().microsecondsSinceEpoch & 0x7fffffff);
    // A new game (rematch, rule change) is a new save; the old one stays.
    _seed = s;
    _log = const [];
    _save = null;
    _autosaveOff = false;
    _saveNoticeShown = false;
    state = _setup.newGame(s);
    _resetTable();
    notifyListeners();
  }

  /// Continues [save]: the state comes from replaying it, and autosave
  /// carries on with the same save, seed and log. Returns `false` (leaving
  /// the table untouched) when the save cannot be replayed or is over.
  bool resume(GameSave save) {
    final replay = SaveReplayer.replay(save);
    if (!replay.resumable) {
      return false;
    }
    _setup = save.setup;
    _seed = save.seed;
    _log = save.log;
    _save = save;
    _autosaveOff = false;
    _saveNoticeShown = false;
    state = replay.state!;
    _resetTable();
    rollerSeat = state.currentSeat;
    final now = _clock();
    if (banked) {
      // Chips that were on the table are simply there, not flying in.
      tray.reconcile(state.currentSeat, state.bank, now);
    }
    if (state.awaitingMove) {
      if (banked) {
        _enterMoving();
      } else {
        legal = Engine.legalMoves(state);
        phase = GamePhase.awaitingMove;
      }
    } else if (state.awaitingRoll) {
      phase = GamePhase.awaitingRoll;
    }
    notifyListeners();
    return true;
  }

  /// Everything that belongs to the table rather than the game: animation
  /// state, toasts, tray, timers. [state] is already set.
  void _resetTable() {
    _aiDueMs = null;
    _passAtMs = null;
    _queue.clear();
    // An answer for the old game must never be played in the new one.
    _ai.cancel();
    if (_hasSearchingAi && !_replay) {
      _ai.warmUp();
    }
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
  }

  /// Test hook: puts the table in [loaded] (a state with a pending die or,
  /// with banked rolls, in the moving phase) as if it had been rolled.
  @visibleForTesting
  void debugLoad(GameState loaded) {
    _autosaveOff = true;
    _queue.clear();
    _passAtMs = null;
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
    if (_replay || phase != GamePhase.awaitingRoll) {
      return;
    }
    // A person's roll goes ahead at once: what is left of the last sequence
    // (a hold, a fading effect) is cut short. The dock tap skips a long one
    // first, and the AI waits for the queue, so this only trims the tail.
    _cutQueue();
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
    diceStartMs = _clock();
    // The die tumbles, then its face is shown: nothing else starts before.
    _queue
      ..add(BeatKind.roll, timeline.settleMs, diceStartMs)
      ..add(
        BeatKind.reveal,
        timeline.durationMs - timeline.settleMs,
        diceStartMs,
      );
    _diceImpactFired = false;
    message = null;
    phase = GamePhase.rolling;
    // The die leaves the hand: the throw sound covers the flight, the table
    // impacts follow at the first impact (tick).
    feedback.sound(SfxEvent.diceThrow);
    notifyListeners();
  }

  /// Quick-roll: skips a running roll to its settle (the result is the same,
  /// it only arrives sooner). Ignored outside a roll.
  void quickRoll() {
    if (_replay || phase != GamePhase.rolling) {
      return;
    }
    _skipOnce();
  }

  /// Whether a tap now should skip the running sequence rather than act:
  /// a roll or a move is playing, or the queue has more than
  /// `Pacing.skipMinRemainingMs` left. In the last stretch a tap acts.
  bool get _wantsSkip =>
      phase == GamePhase.rolling ||
      phase == GamePhase.moving ||
      _queue.remainingMs(_clock()) > Pacing.skipMinRemainingMs;

  /// Tap-to-skip: ends the running sequence (the roll, a hop and its
  /// effects, the "No move" hold) at once. When that starts the next beat
  /// (a roll's result may start a move) it is skipped too, a few times over,
  /// until the table waits for a person or a think time. A sequence that has
  /// less than `Pacing.skipMinRemainingMs` left is left to finish. Returns
  /// whether anything was skipped.
  bool skip() {
    if (_replay) {
      return false;
    }
    var skipped = false;
    for (var i = 0; i < 8; i++) {
      final now = _clock();
      if (_queue.remainingMs(now) <= Pacing.skipMinRemainingMs ||
          !_skipOnce()) {
        break;
      }
      skipped = true;
    }
    return skipped;
  }

  /// Ends what is left of the queue (at most the last 250 ms of a sequence
  /// when a person acts) without moving the clock, then passes a turn that
  /// was waiting for its hold to finish. A fading effect may play on for
  /// that quarter second; nothing is cut off abruptly.
  void _cutQueue() {
    _queue.clear();
    if (_passAtMs != null) {
      _passAtMs = null;
      _activate(state.currentSeat);
    }
  }

  /// Plays a move a person chose: it starts at once, ahead of whatever is
  /// left of the die's reveal or a fading effect (a tap during the last
  /// 250 ms of a sequence is not lost).
  void _playTapped(Move move) {
    _cutQueue();
    _startMove(move);
  }

  /// Moves the clock to the end of everything queued and lets the controller
  /// react. Returns whether time moved.
  bool _skipOnce() {
    final jump = _queue.skip(_clock());
    if (jump <= 0) {
      return false;
    }
    // The skipped bounces are not felt either; only the settle click plays.
    _diceImpactFired = true;
    _skewMs += jump;
    tick();
    return true;
  }

  /// A tap on seat [seat]'s dock: rolls (or quick-rolls) when it is that
  /// seat's turn, otherwise only flashes the dock.
  void dockTap(int seat) {
    if (_replay) {
      return;
    }
    if (seat == activeSeat) {
      if (_wantsSkip) {
        // A tap on the dock while something plays: skip through it.
        skip();
        return;
      }
      if (phase == GamePhase.awaitingRoll) {
        if (aiTurn) {
          // The computer rolls by itself.
          pulseDock(seat);
        } else {
          roll();
        }
        return;
      }
      if (banked && phase == GamePhase.awaitingMove && !aiTurn) {
        // The live die is the roll button, but the bank has to be spent
        // first: it shakes, and so does the tray.
        final now = _clock();
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
    dockPulseMs[seat] = _clock();
  }

  /// Makes [seat] the one on turn, starting the dock handoff.
  void _activate(int seat) {
    if (seat == diceSeat) {
      return;
    }
    prevActiveSeat = diceSeat;
    diceSeat = seat;
    activeSinceMs = _clock();
  }

  /// Tap reach (cells, as a radius) at the old token size; the board view
  /// passes a wider one so every token is at least a 48 dp target.
  static const double _baseReach = 0.8;
  double _reach = _baseReach;

  /// Handles a tap at board position [grid] (in cells). Returns whether a
  /// token was chosen.
  ///
  /// While a roll is due the tap only flashes the dock of the seat on turn;
  /// while a token is to be chosen, a tap on a token that cannot move nudges
  /// it (with a faint red ring and a double tick).
  bool tapAt(Pt grid, {double reach = _baseReach}) {
    _reach = reach < _baseReach ? _baseReach : reach;
    if (_replay) {
      return false;
    }
    if (_wantsSkip) {
      // A tap while something plays skips through it (a long sequence only).
      skip();
      return false;
    }
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
        _playTapped(picked);
        return true;
      }
      notifyListeners();
    }
    if (banked) {
      return _tapBanked(grid);
    }
    final token = _nearestToken(legal, grid);
    if (_tapConfirmsPreview(grid, token)) {
      _playTapped(preview!.move);
      return true;
    }
    if (token == null) {
      _dropPreview();
      _illegalTap(grid);
      return false;
    }
    final mine = [
      for (final m in legal)
        if (m.owner == token.$1 && m.moves(token.$2)) m,
    ];
    if (mine.length == 1) {
      // First tap: show where it would go. A second tap plays it.
      _showPreview(mine.single);
      return false;
    }
    _dropPreview();
    _promptVariants(mine);
    return false;
  }

  /// Opens the preview of [move]: ring on its landing square, trail over the
  /// squares it crosses, a distinct ring when it captures.
  void _showPreview(Move move) {
    preview = MovePreview.of(state, move, geometry: _geo);
    previewStartMs = _clock();
    feedback.play(HapticEvent.select);
    notifyListeners();
  }

  void _dropPreview() {
    if (preview != null) {
      preview = null;
      notifyListeners();
    }
  }

  /// Whether a tap at [grid] (on [token], the nearest movable one, if any)
  /// plays the previewed move: a tap on the previewed token again, or on its
  /// destination ring when no other movable token is under the finger.
  bool _tapConfirmsPreview(Pt grid, (int, int)? token) {
    final p = preview;
    if (p == null) {
      return false;
    }
    if (token != null) {
      return p.isFor(token.$1, token.$2);
    }
    final reach = _reach > 0.9 ? _reach : 0.9;
    return p.destination.distanceTo(grid) <= reach;
  }

  /// The token (owner, index) of [moves] nearest to [grid], within reach of a
  /// tap; both tokens of a moving blockade count.
  (int, int)? _nearestToken(Iterable<Move> moves, Pt grid) {
    (int, int)? best;
    var bestDistance = _reach;
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

  /// Drops the destination choice and the move preview (both are answers to
  /// the same question: which move?).
  void _clearVariants() {
    variants = const [];
    variantPoints = const [];
    preview = null;
  }

  Move? _pickVariant(Pt grid) {
    Move? best;
    var bestDistance = _reach > 0.9 ? _reach : 0.9;
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
    if (_tapConfirmsPreview(grid, token)) {
      _playTapped(preview!.move);
      return true;
    }
    if (token == null) {
      _dropPreview();
      _illegalTap(grid);
      return false;
    }
    final result = c.tapToken(token.$1, token.$2);
    switch (result.kind) {
      case TokenTapKind.variants:
        _dropPreview();
        _promptVariants(result.moves!);
        return false;
      case TokenTapKind.spend:
        _showPreview(result.move!);
        return false;
      case TokenTapKind.select:
        preview = null;
        _syncSelection();
        feedback.play(HapticEvent.select);
        notifyListeners();
        return false;
      case TokenTapKind.prompt:
        tray.prompt(state.currentSeat, _clock());
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
    if (_replay ||
        !banked ||
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
      tray.shake(seat, _clock());
      feedback.play(HapticEvent.illegal);
    }
  }

  /// Whether [seat]'s chips take taps now.
  bool trayTappable(int seat) =>
      !_replay &&
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
    tray.select(state.currentSeat, choice?.selected, _clock());
  }

  /// Gives each seat's tray the width its layout slot has (chips per row).
  void syncTrayCapacity(List<double> chips) {
    final now = _clock();
    for (var seat = 0; seat < chips.length && seat < seatCount; seat++) {
      tray.setCapacity(seat, chips[seat], now);
    }
  }

  /// A tap during a choice that hit a token with no move (an opponent's, or
  /// one of the mover's own that this roll cannot move).
  void _illegalTap(Pt grid) {
    int? seat;
    var index = 0;
    var nearest = _reach;
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
      FxNudge(seat: seat, index: index, startMs: _clock()),
      resting[seat][index],
      spec,
    );
    feedback.play(HapticEvent.illegal);
  }

  /// Advances time-based transitions; called every frame by the screen.
  void tick() {
    final now = _clock();
    PaintProbe.nextFrame();
    clock.value = now;
    fx.prune(now, spec);
    tray.prune(now, spec);
    final pass = _passAtMs;
    if (pass != null && now >= pass) {
      // The roll that had no move has been shown long enough: pass the turn.
      _passAtMs = null;
      _activate(state.currentSeat);
      notifyListeners();
    }
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
      final hops = plan!.hopTimesMs;
      while (_hopsFired < hops.length && t >= hops[_hopsFired]) {
        _hopsFired++;
        feedback.sound(SfxEvent.hop);
      }
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
  ///
  /// Rolling is automatic. A move is a small state machine in [_ai]: the
  /// request goes to the worker the moment the choice is due, and the answer
  /// plays after `max(think time, compute time)`, so the search hides inside
  /// the usual pause. A late, crashed or nonsensical worker means the
  /// baseline bot plays; the game never waits for the AI.
  void _driveAi(double now) {
    if (_replay || !aiTurn) {
      _aiDueMs = null;
      _ai.cancel();
      return;
    }
    if (phase == GamePhase.awaitingMove && _autoMove != null) {
      // A forced spend of the bank goes by itself.
      return;
    }
    if (phase == GamePhase.awaitingRoll) {
      // It thinks once the table is quiet, never while something still plays.
      final due = _aiDueMs ??= _queue.freeAtMs(now) + _think.next(spec);
      if (now >= due && !_queue.busy(now)) {
        _aiDueMs = null;
        roll();
      }
      return;
    }
    if (legal.isEmpty) {
      return;
    }
    if (!_ai.busy) {
      _ai.begin(
        nowMs: now,
        thinkMs: _think.next(spec),
        state: state,
        legal: legal,
        level: _setup.configOf(state.currentSeat).aiLevel,
      );
    }
    if (_queue.busy(now)) {
      return;
    }
    final move = _ai.poll(now, state);
    if (move != null) {
      _startMove(move);
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
      phase = GamePhase.awaitingMove;
      if (legal.length == 1 && (autoMoveSingle || isAi(state.currentSeat))) {
        // Nothing to choose: it goes by itself once the die has shown its
        // face (the reveal beat), never over it.
        final at = _queue.freeAtMs(_clock());
        if (at <= _clock()) {
          _startMove(legal.first);
          return;
        }
        _autoMove = legal.first;
        _autoMoveAtMs = at;
      }
    } else {
      final now = _clock();
      message = result.outcome == RollOutcome.tripleSixForfeit
          ? 'Three sixes'
          : 'No move';
      toasts[rollerSeat] = DockToast(message!, now);
      noMoveSeat = dimSeat;
      noMoveMs = now;
      feedback.play(HapticEvent.noMove);
      _holdThenPass(now);
      phase = GamePhase.awaitingRoll;
    }
    notifyListeners();
  }

  /// A turn with nothing to play: the roll stays on the table for about
  /// 600 ms after the die settles (the reveal beat is part of that), then the
  /// turn passes. The queue stays busy meanwhile, so no roll can start.
  void _holdThenPass(double now) {
    final extra = Pacing.noMoveMs(spec) - _queue.remainingMs(now);
    _queue.add(BeatKind.hold, extra, now);
    final at = _queue.freeAtMs(now);
    if (at <= now) {
      _activate(state.currentSeat);
    } else {
      _passAtMs = at;
    }
  }

  /// Banked rolls: applies the outcome of one roll (the die only joined the
  /// bank, or the sequence ended, or it was wiped or reverted).
  void _finishBankedRoll(GameState before, RollResult result) {
    final now = _clock();
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
        _holdThenPass(now);
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
        _ai.cancel();
        toasts[seat] = DockToast.undone(now);
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
          _queue.add(BeatKind.move, delay + anim.totalMs, now);
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
    final now = _clock();
    final seat = state.currentSeat;
    tray.reconcile(seat, state.bank, now);
    final c = BankChoice.of(state);
    choice = c;
    legal = c.legal;
    tray.select(seat, c.selected, now);
    _autoMove = c.forced;
    final spendAt = now + (spec.reducedMotion ? 0 : spec.tray.autoSpendMs);
    final free = _queue.freeAtMs(now);
    _autoMoveAtMs = spendAt > free ? spendAt : free;
    phase = GamePhase.awaitingMove;
  }

  void _startMove(Move move) {
    final before = state;
    final entry =
        _autosaveOff || _saves == null ? null : Engine.logEntry(before, move);
    final after = Engine.apply(before, move);
    if (entry != null) {
      _autosave(entry, after);
    }
    final start = _clock();
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
    // The hop (and a capture or finish with it), then whatever is left of
    // its effects: one beat after the other, so the next roll never plays
    // over them.
    _queue.add(BeatKind.move, newPlan.totalMs, start);
    _queue.add(
      BeatKind.tail,
      newPlan.effects.endMs - (start + newPlan.totalMs),
      start,
    );
    _after = after;
    planStartMs = start;
    _impactFired = false;
    _hopsFired = 0;
    legal = const [];
    phase = GamePhase.moving;
    notifyListeners();
  }

  /// Logs [entry] and queues the whole save. [after] is exactly what
  /// `Engine.apply` returned (never a post-roll state), so the save's check
  /// fingerprint matches what a replay produces. Never blocks play: the
  /// write is queued and a failure only raises one quiet notice.
  void _autosave(MoveLogEntry entry, GameState after) {
    final queue = _saves;
    if (queue == null) {
      return;
    }
    try {
      final wall = _wall();
      final next = (_save ??
              GameSave.begin(
                id: GameSave.newId(wall),
                now: wall,
                setup: _setup,
                seed: _seed,
              ))
          .withEntry(entry, after, wall);
      _save = next;
      _log = next.log;
      queue.put(next);
    } on Object {
      _onSaveError(StateError('autosave failed'));
    }
  }

  void _onSaveError(Object error) {
    if (_saveNoticeShown) {
      return;
    }
    _saveNoticeShown = true;
    final seat = state.currentSeat;
    toasts[seat] = DockToast('Not saved', _clock());
    notifyListeners();
  }

  void _finishMove() {
    state = _after!;
    _after = null;
    plan = null;
    _refreshLayout();
    legal = const [];
    _activate(state.currentSeat);
    if (banked && !_replay && !state.isOver && state.awaitingMove) {
      // More dice to spend.
      _enterMoving();
      notifyListeners();
      return;
    }
    phase = state.isOver ? GamePhase.gameOver : GamePhase.awaitingRoll;
    if (phase == GamePhase.gameOver) {
      feedback.play(HapticEvent.win);
      gameOverMs = _clock();
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

  // ---- Replay (docs/ludo-saves.md section 11) ------------------------------

  /// Shows [shown] at once, without animation: the table is reset to that
  /// state (tokens at rest, nothing flying, the tray holding the bank of a
  /// banked turn that is mid-spend). [rolls] maps a seat to the face of the
  /// last die it played, for the ghost dice in the docks. A game that is
  /// over shows its rank badges, without confetti or a haptic.
  void replayShow(GameState shown, {Map<int, int> rolls = const {}}) {
    assert(_replay, 'replayShow is for replay controllers');
    // A scrub or a jump plays nothing, not even a cue still waiting.
    feedback.cancelSounds();
    state = shown;
    _resetTable();
    rollerSeat = shown.currentSeat;
    for (final entry in rolls.entries) {
      seatDice[entry.key] = _ghostDie(entry.key, entry.value);
    }
    if (banked && shown.bank.isNotEmpty) {
      tray.reconcile(shown.currentSeat, shown.bank, _clock());
    }
    if (shown.isOver) {
      phase = GamePhase.gameOver;
    }
    notifyListeners();
  }

  /// Plays one decision with the normal animations: the table takes [ready]
  /// (the state with the roll made, no animation; see `ReplayStep.ready`)
  /// and [move] hops, captures or reaches home as it would in a live game.
  /// A move still animating is settled first. [roller] rolled [dice].
  /// [reverted] says that the turn was undone since the last decision
  /// (banked dead end): the tokens are simply back, with a notice.
  void replayPlay(
    GameState ready,
    Move move, {
    required int roller,
    required int dice,
    bool reverted = false,
  }) {
    assert(_replay, 'replayPlay is for replay controllers');
    replaySettle();
    final now = _clock();
    if (reverted) {
      toasts[state.currentSeat] = DockToast.undone(now);
    }
    state = ready;
    _activate(ready.currentSeat);
    rollerSeat = roller;
    lastRoll = dice;
    seatDice[roller] = _ghostDie(roller, dice);
    message = null;
    _refreshLayout();
    if (banked) {
      tray.reconcile(roller, ready.bank, now);
    }
    _startMove(move);
  }

  /// Finishes a move that is still animating (its effects keep playing).
  /// Does nothing when none is.
  void replaySettle() {
    if (phase == GamePhase.moving && _after != null) {
      _finishMove();
    }
  }

  /// Whether a replayed move is animating right now.
  bool get replayMoving => phase == GamePhase.moving;

  Dice3dTimeline _ghostDie(int seat, int face) => Dice3dTimeline(
        value: face,
        seed: (seat * 7919 + face * 104729) & 0x7fffffff,
        spec: spec,
      );

  /// Seat of the winning player (or team's first seat); `null` before the end.
  int? get winnerSeat {
    final winners = state.winners;
    return winners == null || winners.isEmpty ? null : winners.first;
  }

  /// Starts the same table again with a fresh seed (the game-over "Rematch").
  void rematch() => newGame();

  @override
  void dispose() {
    _saveErrors?.cancel();
    _ai.dispose();
    clock.dispose();
    feedback.dispose();
    super.dispose();
  }
}
