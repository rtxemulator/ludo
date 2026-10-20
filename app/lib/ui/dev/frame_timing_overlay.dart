import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ludo/ui/core/frame_stats.dart';

/// Optional profiling overlay (Settings > Frame timing overlay). It listens
/// to the engine's `FrameTiming` reports
/// (`SchedulerBinding.addTimingsCallback`, no package) and shows the last
/// ~2 s: fps, dropped and slow frames, UI and raster thread times and how long
/// the game's own painters take to record a frame (budget 4 ms).
///
/// Only mounted while the setting is on, so it costs nothing otherwise.
class FrameTimingOverlay extends StatefulWidget {
  const FrameTimingOverlay({super.key});

  @override
  State<FrameTimingOverlay> createState() => _FrameTimingOverlayState();
}

class _FrameTimingOverlayState extends State<FrameTimingOverlay> {
  late final FrameStats _stats;
  Timer? _timer;
  double? _lastStartMs;
  FrameSummary _summary = FrameSummary.empty;

  @override
  void initState() {
    super.initState();
    var refresh = 60.0;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) {
      final hz = views.first.display.refreshRate;
      if (hz.isFinite && hz >= 30) {
        refresh = hz;
      }
    }
    _stats = FrameStats(budgetMs: 1000 / refresh);
    PaintProbe.reset();
    PaintProbe.enabled = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() => _summary = _stats.summary());
      }
    });
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      final start =
          t.timestampInMicroseconds(ui.FramePhase.vsyncStart) / 1000.0;
      final last = _lastStartMs;
      _lastStartMs = start;
      _stats.add(
        FrameSample(
          buildMs: t.buildDuration.inMicroseconds / 1000.0,
          rasterMs: t.rasterDuration.inMicroseconds / 1000.0,
          totalMs: t.totalSpan.inMicroseconds / 1000.0,
          intervalMs: last == null ? null : start - last,
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    PaintProbe.enabled = false;
    PaintProbe.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final paintAvg = PaintProbe.averageMs;
    final paintWorst = PaintProbe.worstMs;
    final paintBad = paintWorst > FrameSummary.paintBudgetMs;
    final lines = [
      '${s.fps.toStringAsFixed(0)} fps  drop ${s.droppedFrames}  '
          'slow ${s.slowFrames}  /${s.frames}',
      'ui ${s.avgBuildMs.toStringAsFixed(1)}  '
          'raster ${s.avgRasterMs.toStringAsFixed(1)} ms',
      'p95 ${s.p95TotalMs.toStringAsFixed(1)}  '
          'worst ${s.worstTotalMs.toStringAsFixed(1)} '
          '(budget ${s.budgetMs.toStringAsFixed(1)})',
      'paint ${paintAvg.toStringAsFixed(1)} avg  '
          '${paintWorst.toStringAsFixed(1)} worst (max '
          '${FrameSummary.paintBudgetMs.toStringAsFixed(0)})',
    ];
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            lines.join('\n'),
            style: TextStyle(
              color: paintBad || s.droppedFrames > 0
                  ? const Color(0xFFFF8A80)
                  : const Color(0xFFB9F6CA),
              fontSize: 10.5,
              height: 1.25,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
