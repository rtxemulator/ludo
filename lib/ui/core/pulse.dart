/// Legal-move pulse as a pure function of time. No Flutter.
library;

import 'curves.dart';
import 'motion_spec.dart';

/// Legal-move pulse (shared by every highlighted token).
class PulseSample {
  const PulseSample({required this.radius, required this.opacity});

  /// Ring radius in cells.
  final double radius;
  final double opacity;

  static PulseSample at(double tMs, MotionSpec spec) {
    final phase = (tMs % spec.pulsePeriodMs) / spec.pulsePeriodMs;
    final w = easeInOutSine(phase < 0.5 ? phase * 2 : (1 - phase) * 2);
    return PulseSample(
      radius: spec.pulseMinRadius + spec.pulseRadiusGain * w,
      opacity: spec.pulseMinOpacity + spec.pulseOpacityGain * w,
    );
  }
}
