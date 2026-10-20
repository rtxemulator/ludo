/// Frame-timing statistics for the optional in-app overlay. Pure Dart, no
/// Flutter: the app feeds it `FrameTiming` numbers, the overlay prints the
/// [FrameSummary]. Spec: docs/ludo-ui-ux.md section 11 (P7).
library;

import 'dart:math' as math;

/// One frame as the engine measured it (milliseconds).
class FrameSample {
  const FrameSample({
    required this.buildMs,
    required this.rasterMs,
    required this.totalMs,
    this.intervalMs,
    this.paintMs = 0,
  });

  /// UI thread: build + layout + paint recording.
  final double buildMs;

  /// Raster thread.
  final double rasterMs;

  /// Vsync start to raster finish.
  final double totalMs;

  /// Time since the previous frame started, when known.
  final double? intervalMs;

  /// Time spent inside the game's own `CustomPainter.paint` calls.
  final double paintMs;
}

/// Aggregates over the window kept by [FrameStats].
class FrameSummary {
  const FrameSummary({
    required this.frames,
    required this.fps,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.p95TotalMs,
    required this.worstTotalMs,
    required this.avgPaintMs,
    required this.worstPaintMs,
    required this.slowFrames,
    required this.droppedFrames,
    required this.budgetMs,
  });

  static const FrameSummary empty = FrameSummary(
    frames: 0,
    fps: 0,
    avgBuildMs: 0,
    avgRasterMs: 0,
    p95TotalMs: 0,
    worstTotalMs: 0,
    avgPaintMs: 0,
    worstPaintMs: 0,
    slowFrames: 0,
    droppedFrames: 0,
    budgetMs: 1000 / 60,
  );

  final int frames;
  final double fps;
  final double avgBuildMs;
  final double avgRasterMs;
  final double p95TotalMs;
  final double worstTotalMs;
  final double avgPaintMs;
  final double worstPaintMs;

  /// Frames whose build or raster phase alone overran the budget.
  final int slowFrames;

  /// Frames that arrived later than 1.5 budgets after the previous one
  /// (a visible hitch), pauses of the ticker excluded.
  final int droppedFrames;

  /// Frame budget the numbers were judged against.
  final double budgetMs;

  /// The paint budget of the design doc.
  static const double paintBudgetMs = 4;

  bool get paintOverBudget => worstPaintMs > paintBudgetMs;
}

/// Rolling window of the last [capacity] frames.
class FrameStats {
  FrameStats({this.capacity = 120, this.budgetMs = 1000 / 60})
      : assert(capacity > 0);

  final int capacity;

  /// `1000 / refreshRate`.
  final double budgetMs;

  /// An interval longer than this is a pause (nothing animated), not a hitch.
  static const double pauseMs = 250;

  final List<FrameSample> _samples = [];

  int get length => _samples.length;

  void add(FrameSample sample) {
    _samples.add(sample);
    if (_samples.length > capacity) {
      _samples.removeAt(0);
    }
  }

  void clear() => _samples.clear();

  FrameSummary summary() {
    if (_samples.isEmpty) {
      return FrameSummary.empty;
    }
    var build = 0.0;
    var raster = 0.0;
    var paint = 0.0;
    var worstPaint = 0.0;
    var slow = 0;
    var dropped = 0;
    var intervalSum = 0.0;
    var intervals = 0;
    for (final s in _samples) {
      build += s.buildMs;
      raster += s.rasterMs;
      paint += s.paintMs;
      worstPaint = math.max(worstPaint, s.paintMs);
      if (s.buildMs > budgetMs || s.rasterMs > budgetMs) {
        slow++;
      }
      final gap = s.intervalMs;
      if (gap != null && gap < pauseMs) {
        intervalSum += gap;
        intervals++;
        if (gap > budgetMs * 1.5) {
          dropped++;
        }
      }
    }
    final totals = [for (final s in _samples) s.totalMs]..sort();
    final p95 =
        totals[math.min(totals.length - 1, (totals.length * 0.95).floor())];
    final n = _samples.length;
    return FrameSummary(
      frames: n,
      fps: intervals == 0 || intervalSum == 0
          ? 0
          : 1000 * intervals / intervalSum,
      avgBuildMs: build / n,
      avgRasterMs: raster / n,
      p95TotalMs: p95,
      worstTotalMs: totals.last,
      avgPaintMs: paint / n,
      worstPaintMs: worstPaint,
      slowFrames: slow,
      droppedFrames: dropped,
      budgetMs: budgetMs,
    );
  }
}

/// Measures the time the game's own painters spend recording a frame.
///
/// Off by default (a painter then pays only a bool check). The controller
/// calls [nextFrame] once per tick; each painter brackets its `paint` with
/// [start] / [stop].
class PaintProbe {
  PaintProbe._();

  static bool enabled = false;

  static final Stopwatch _clock = Stopwatch()..start();
  static double _accumulatedMs = 0;
  static double _lastFrameMs = 0;
  static const int _window = 120;
  static final List<double> _recent = [];

  /// Microsecond stamp to hand back to [stop] (0 when disabled).
  static int start() => enabled ? _clock.elapsedMicroseconds : 0;

  static void stop(int stamp) {
    if (enabled) {
      _accumulatedMs += (_clock.elapsedMicroseconds - stamp) / 1000;
    }
  }

  /// Closes the frame that was just painted and starts a new one; returns the
  /// closed frame's paint time.
  static double nextFrame() {
    _lastFrameMs = _accumulatedMs;
    _accumulatedMs = 0;
    if (enabled) {
      _recent.add(_lastFrameMs);
      if (_recent.length > _window) {
        _recent.removeAt(0);
      }
    }
    return _lastFrameMs;
  }

  /// Mean paint time over the last 120 frames (0 when none).
  static double get averageMs =>
      _recent.isEmpty ? 0 : _recent.fold(0.0, (a, b) => a + b) / _recent.length;

  /// Worst paint time over the last 120 frames.
  static double get worstMs => _recent.fold(0.0, math.max);

  /// Paint time of the most recently closed frame.
  static double get lastFrameMs => _lastFrameMs;

  static void reset() {
    _accumulatedMs = 0;
    _lastFrameMs = 0;
    _recent.clear();
  }
}
