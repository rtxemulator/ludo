import 'package:flutter/foundation.dart';
import 'package:ludo/storage/storage.dart';
import 'package:ludo/ui/core/scaled_clock.dart';

import '../haptics/haptics_service.dart';
import 'game_controller.dart';

/// Plays a [ReplayScript] on a presentation-only [GameController].
///
/// The table model never rolls, never reads taps, never starts an AI worker
/// and never saves. Moving forward by one decision loads the state before it
/// and plays the logged move with the normal hop, capture and home
/// animations; stepping back, jumping and scrubbing show a state at once.
/// Playback speed scales the clock the table runs on, so every animation
/// follows it. Position `k` means "after decision `k`" (`0` is the start).
class ReplayController extends ChangeNotifier {
  ReplayController({
    required ReplayScript script,
    double Function()? clock,
    bool haptics = true,
    HapticsService? hapticsService,
  }) : this._(
          script,
          ScaledClock(clock ?? _stopwatch()),
          haptics,
          hapticsService,
        );

  ReplayController._(
    this.script,
    ScaledClock clock,
    bool haptics,
    HapticsService? hapticsService,
  )   : _clock = clock,
        game = GameController(
          setup: script.save.setup,
          seed: script.save.seed,
          now: clock.now,
          haptics: haptics,
          hapticsService: hapticsService,
          replay: true,
        ) {
    game.replayShow(script.at(0));
  }

  static double Function() _stopwatch() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds / 1000.0;
  }

  /// Pause between two decisions while playing (at 1x; the clock scales it).
  static const double gapMs = 450;

  /// The speeds the viewer offers.
  static const List<double> speeds = [1, 2, 4];

  final ReplayScript script;
  final ScaledClock _clock;

  /// The table model the screen paints.
  final GameController game;

  int _position = 0;
  bool _playing = false;
  bool _animating = false;
  double _nextAtMs = 0;
  bool _disposed = false;

  /// Decisions applied: the table shows the state after decision `position`
  /// (while decision `position` is hopping, it is on its way there).
  int get position => _position;

  /// Playable decisions (`N`).
  int get length => script.length;

  bool get atStart => _position == 0;
  bool get atEnd => _position >= script.length;
  bool get playing => _playing;
  double get speed => _clock.speed;

  /// The decision at [position], or `null` at the start.
  ReplayStep? get step => _position == 0 ? null : script.step(_position);

  /// Whether the replay stops before the game did (damaged or refused log).
  bool get partial => script.partial;

  // ---- Controls -----------------------------------------------------------

  void play() {
    if (_playing || script.length == 0) {
      return;
    }
    if (atEnd) {
      _jump(0);
    }
    _playing = true;
    _nextAtMs = _clock.now();
    notifyListeners();
  }

  void pause() {
    if (!_playing) {
      return;
    }
    _playing = false;
    notifyListeners();
  }

  void togglePlay() => _playing ? pause() : play();

  set speed(double value) {
    if (value <= 0 || value == _clock.speed) {
      return;
    }
    _clock.speed = value;
    notifyListeners();
  }

  /// One decision forward, animated. Pauses playback.
  void stepForward() {
    _playing = false;
    if (atEnd) {
      notifyListeners();
      return;
    }
    _forward();
  }

  /// One decision back, shown at once. Pauses playback.
  void stepBack() {
    _playing = false;
    _jump(_position - 1);
  }

  void toStart() {
    _playing = false;
    _jump(0);
  }

  void toEnd() {
    _playing = false;
    _jump(script.length);
  }

  /// Shows position [k] at once (scrubbing). Pauses playback.
  void seek(int k) {
    _playing = false;
    _jump(k);
  }

  // ---- Frame --------------------------------------------------------------

  /// Called every frame by the screen's ticker.
  void tick() {
    if (_disposed) {
      return;
    }
    game.tick();
    final now = _clock.now();
    if (_animating && !game.replayMoving) {
      _animating = false;
      _nextAtMs = now + gapMs;
      if (atEnd) {
        // Auto-pause at the end.
        _playing = false;
      }
      notifyListeners();
    }
    if (!_playing || game.replayMoving || now < _nextAtMs) {
      return;
    }
    if (atEnd) {
      _playing = false;
      notifyListeners();
      return;
    }
    _forward();
  }

  /// Whether the screen's ticker has work to do (the table's own rule: the
  /// idle animations run until the game is over and the confetti is done).
  bool get needsTicker => game.needsTicker;

  // ---- Internals ----------------------------------------------------------

  void _forward() {
    game.replaySettle();
    _position++;
    final s = script.step(_position);
    game.replayPlay(
      s.ready,
      s.move,
      roller: s.roller,
      dice: s.dice,
      reverted: s.revertedBefore,
    );
    _animating = true;
    notifyListeners();
  }

  void _jump(int k) {
    final target = k.clamp(0, script.length);
    if (target == _position && !_animating) {
      notifyListeners();
      return;
    }
    _position = target;
    _animating = false;
    _nextAtMs = _clock.now() + gapMs;
    game.replayShow(script.at(target), rolls: _rollsAt(target));
    notifyListeners();
  }

  /// The face each seat last played up to position [k].
  Map<int, int> _rollsAt(int k) {
    final rolls = <int, int>{};
    for (var i = k; i >= 1 && rolls.length < 4; i--) {
      final entry = script.step(i).entry;
      rolls.putIfAbsent(entry.seat, () => entry.dice);
    }
    return rolls;
  }

  @override
  void dispose() {
    _disposed = true;
    _playing = false;
    game.dispose();
    super.dispose();
  }
}
