/// The banked-roll tray: die chips beside a dock, as pure functions of time.
/// No Flutter. Spec: docs/ludo-ui-ux.md section 10.
///
/// The tray is a model of *view* state only (which chips exist, when they
/// appeared, which one is selected, how they leave); the dice themselves
/// live in `GameState.bank`. The controller keeps the two in step and the
/// painter only samples [BankTray.pose].
///
/// Lengths are in **chip edges** (one chip is `1` wide and tall). `x` runs
/// along the tray (the player's left to right), `y` points at the player's
/// own table edge; the painter turns that frame to the seat.
library;

import 'dart:math' as math;

import 'curves.dart';
import 'motion_spec.dart';
import 'pt.dart';

/// How a chip leaves the tray.
enum ChipExit {
  /// Spent on a token: flies to it and dissolves.
  spend,

  /// Triple-six: the whole bank bursts.
  wipe,

  /// Dead end: the whole bank shrinks away.
  revert,
}

/// Slot of chip [index] of [count] along the tray, `0` = tray centre. A tray
/// [capacity] chips wide keeps the pitch at one chip plus [gap] and squeezes
/// (overlaps) the chips when there are too many to fit.
double fanX(int index, int count, double capacity, {double gap = 0.12}) {
  if (count <= 1) {
    return 0;
  }
  final full = 1 + gap;
  final fit = (capacity - 1) / (count - 1);
  final pitch = math.max(0.25, math.min(full, fit));
  return (index - (count - 1) / 2) * pitch;
}

/// Tilt (radians) of chip [index] of [count]: a hand of dice, not a ruler.
double fanAngle(int index, int count, MotionSpec spec) {
  final u = index - (count - 1) / 2;
  return (u * spec.tray.fanTilt)
      .clamp(-spec.tray.fanMaxTilt, spec.tray.fanMaxTilt)
      .toDouble();
}

/// Sag (toward the player's edge) of the outer chips of the fan.
double fanY(int index, int count, MotionSpec spec) {
  final u = index - (count - 1) / 2;
  return spec.tray.fanSag * u * u;
}

/// Index of the chip nearest to [x] (chip edges from the tray centre) among
/// [count] chips in a tray [capacity] wide; the later (topmost) chip wins a
/// tie. `-1` for an empty tray.
int hitChip(double x, int count, double capacity, {double gap = 0.12}) {
  var best = -1;
  var bestDistance = double.infinity;
  for (var i = 0; i < count; i++) {
    final d = (fanX(i, count, capacity, gap: gap) - x).abs();
    if (d <= bestDistance + 1e-9) {
      bestDistance = d;
      best = i;
    }
  }
  return best;
}

/// One chip. Fields are the bookkeeping [BankTray] needs; read poses through
/// [BankTray.pose].
class TrayChip {
  TrayChip._({
    required this.id,
    required this.seat,
    required this.value,
    required this.bornMs,
    required double x,
  })  : fromX = x,
        toX = x,
        slideMs = bornMs;

  final int id;
  final int seat;
  final int value;
  final double bornMs;

  double fromX;
  double toX;
  double slideMs;

  /// Fan position (set whenever the tray is laid out).
  int slot = 0;
  int slots = 1;

  double? selectedAtMs;
  double? deselectedAtMs;

  ChipExit? exit;
  double exitMs = 0;
  int exitOrder = 0;
  double exitX = 0;
  double exitSelect = 0;
  Pt? target;

  bool get leaving => exit != null;
}

/// What a chip looks like at one instant.
class ChipPose {
  const ChipPose({
    required this.x,
    required this.y,
    required this.angle,
    required this.scale,
    required this.opacity,
    required this.select,
    this.flight = 0,
    this.target,
  });

  /// Along the tray (chip edges from its centre) and toward the player's own
  /// edge.
  final double x;
  final double y;

  /// Fan tilt, radians.
  final double angle;

  /// Uniform scale: pop, selection lift and flight height are all in here
  /// (height is scale, never a Y offset).
  final double scale;
  final double opacity;

  /// `0..1` selection strength (glow).
  final double select;

  /// `0..1` eased progress of a spent chip toward [target] (board cells);
  /// `0` for a chip that is not flying.
  final double flight;
  final Pt? target;
}

/// The chips of all four trays.
class BankTray {
  /// The motion spec the layout slides use; the controller keeps it equal to
  /// its own (reduced motion switches slides off).
  MotionSpec spec = MotionSpec.standard;

  /// Tray width per seat in chip edges (set from the layout).
  final List<double> capacity = List.filled(4, 5.0);

  final List<TrayChip> _chips = [];
  final List<double> _promptMs = List.filled(4, -1e9);
  final List<double> _shakeMs = List.filled(4, -1e9);
  int _nextId = 0;

  /// Every chip that is still drawn (present and leaving).
  List<TrayChip> get chips => _chips;

  bool get isEmpty => _chips.isEmpty;

  /// Chips of [seat] that are still in the bank, in rolled order.
  List<TrayChip> presentOf(int seat) => [
        for (final c in _chips)
          if (c.seat == seat && !c.leaving) c,
      ];

  /// Values of [presentOf], in order (compare with `GameState.bank`).
  List<int> valuesOf(int seat) => [for (final c in presentOf(seat)) c.value];

  void clear() {
    _chips.clear();
    _promptMs.fillRange(0, 4, -1e9);
    _shakeMs.fillRange(0, 4, -1e9);
  }

  /// Changes the width of [seat]'s tray and re-lays its chips out.
  void setCapacity(int seat, double chips, double now) {
    if ((capacity[seat] - chips).abs() < 1e-6) {
      return;
    }
    capacity[seat] = chips;
    _relayout(seat, now);
  }

  /// A die joined [seat]'s bank: its chip pops in at the end of the row.
  TrayChip append(int seat, int value, double now) {
    final chip = TrayChip._(
      id: _nextId++,
      seat: seat,
      value: value,
      bornMs: now,
      x: 0,
    );
    _chips.add(chip);
    _relayout(seat, now, fresh: chip);
    return chip;
  }

  /// Chip [index] (among the present ones) of [seat] was spent on a token at
  /// board cell [target]; the others close the gap.
  void spendAt(int seat, int index, Pt target, double now) {
    final present = presentOf(seat);
    assert(index >= 0 && index < present.length, 'no such chip');
    final chip = present[index];
    _leave(chip, ChipExit.spend, now, 0);
    chip.target = target;
    _relayout(seat, now);
  }

  /// Every chip of [seat] leaves with [kind] (`wipe` or `revert`).
  void exitAll(int seat, ChipExit kind, double now) {
    var order = 0;
    for (final chip in presentOf(seat)) {
      _leave(chip, kind, now, order++);
    }
  }

  /// Makes [seat]'s present chips match [bank] without any animation. A no-op
  /// when they already do; a safety net, not part of the normal flow.
  void reconcile(int seat, List<int> bank, double now) {
    final have = valuesOf(seat);
    if (have.length == bank.length) {
      var same = true;
      for (var i = 0; i < bank.length; i++) {
        if (have[i] != bank[i]) {
          same = false;
          break;
        }
      }
      if (same) {
        return;
      }
    }
    _chips.removeWhere((c) => c.seat == seat && !c.leaving);
    for (final v in bank) {
      final chip = TrayChip._(
        id: _nextId++,
        seat: seat,
        value: v,
        bornMs: now - 1e6,
        x: 0,
      );
      _chips.add(chip);
    }
    _relayout(seat, now - 1e6);
  }

  /// Selects chip [index] (among the present ones) of [seat], or nothing for
  /// `null`.
  void select(int seat, int? index, double now) {
    final present = presentOf(seat);
    for (var i = 0; i < present.length; i++) {
      final chip = present[i];
      final selected = _isSelected(chip);
      if (i == index) {
        if (!selected) {
          chip.selectedAtMs = now;
          chip.deselectedAtMs = null;
        }
      } else if (selected) {
        chip.deselectedAtMs = now;
      }
    }
  }

  /// Index (among the present ones) of the selected chip of [seat].
  int? selectedIndex(int seat) {
    final present = presentOf(seat);
    for (var i = 0; i < present.length; i++) {
      if (_isSelected(present[i])) {
        return i;
      }
    }
    return null;
  }

  /// "Pick a die": the tray of [seat] swells once.
  void prompt(int seat, double now) => _promptMs[seat] = now;

  /// The tray of [seat] shakes sideways (bank-full tap, unplayable chip).
  void shake(int seat, double now) => _shakeMs[seat] = now;

  /// Drops chips whose exit has finished.
  void prune(double now, MotionSpec spec) {
    _chips.removeWhere(
      (c) => c.exit != null && now >= c.exitMs + _exitTotalMs(c, spec),
    );
  }

  /// Time a chip needs from the call that made it leave until it is gone.
  double exitTotalMs(TrayChip chip, MotionSpec spec) =>
      _exitTotalMs(chip, spec);

  // ---- Layout -------------------------------------------------------------

  bool _isSelected(TrayChip c) =>
      c.selectedAtMs != null &&
      (c.deselectedAtMs == null || c.selectedAtMs! > c.deselectedAtMs!);

  void _relayout(int seat, double now, {TrayChip? fresh}) {
    final present = presentOf(seat);
    final n = present.length;
    for (var i = 0; i < n; i++) {
      final c = present[i];
      final target = fanX(i, n, capacity[seat]);
      if (identical(c, fresh)) {
        c.fromX = target;
        c.toX = target;
      } else {
        c.fromX = _slideX(c, now);
        c.toX = target;
      }
      c.slideMs = now;
      c.slot = i;
      c.slots = n;
    }
  }

  void _leave(TrayChip chip, ChipExit kind, double now, int order) {
    chip.exitX = _slideX(chip, now);
    chip.exitSelect = _isSelected(chip) ? 1 : 0;
    chip.exit = kind;
    chip.exitMs = now;
    chip.exitOrder = order;
  }

  /// Position of [c] along the tray at [now] (it glides between layouts).
  double _slideX(TrayChip c, double now, [MotionSpec? override]) {
    final s = override ?? spec;
    if (s.reducedMotion) {
      return c.toX;
    }
    final u = clamp01((now - c.slideMs) / s.tray.slideMs);
    return c.fromX + (c.toX - c.fromX) * easeOutCubic(u);
  }

  double _exitTotalMs(TrayChip c, MotionSpec spec) {
    switch (c.exit) {
      case ChipExit.spend:
        return spec.reducedMotion ? spec.reducedFadeMs : spec.tray.spendMs;
      case ChipExit.wipe:
        return spec.reducedMotion
            ? spec.reducedFadeMs
            : c.exitOrder * spec.tray.wipeStaggerMs + spec.tray.wipeMs;
      case ChipExit.revert:
        return spec.reducedMotion
            ? spec.reducedFadeMs
            : c.exitOrder * spec.tray.revertStaggerMs + spec.tray.revertMs;
      case null:
        return 0;
    }
  }

  // ---- Sampling -----------------------------------------------------------

  /// Selection strength `0..1` of [chip] at [now].
  double selectAmount(TrayChip chip, double now, MotionSpec spec) {
    final on = chip.selectedAtMs;
    if (on == null) {
      return 0;
    }
    final off = chip.deselectedAtMs;
    final ms = spec.tray.selectMs;
    if (off == null || on > off) {
      return spec.reducedMotion ? 1 : easeOutCubic(clamp01((now - on) / ms));
    }
    return spec.reducedMotion ? 0 : 1 - easeOutCubic(clamp01((now - off) / ms));
  }

  /// Sideways shake (chip edges) of [seat]'s tray at [now].
  double shakeOffset(int seat, double now, MotionSpec spec) {
    final u = (now - _shakeMs[seat]) / spec.tray.shakeMs;
    if (spec.reducedMotion || u < 0 || u >= 1) {
      return 0;
    }
    return spec.tray.shakeAmplitude *
        dampedSine(
          u,
          cycles: spec.tray.shakeCycles,
          decay: spec.tray.shakeDecay,
        );
  }

  /// Extra scale (`0..promptScale`) of [seat]'s chips while it prompts.
  double promptSwell(int seat, double now, MotionSpec spec) {
    final u = (now - _promptMs[seat]) / spec.tray.promptMs;
    if (spec.reducedMotion || u < 0 || u >= 1) {
      return 0;
    }
    return spec.tray.promptScale * math.sin(math.pi * u);
  }

  /// Pose of [chip] at [now]; `null` once it has gone (it is also pruned).
  ChipPose? pose(TrayChip chip, double now, MotionSpec spec) {
    final tray = spec.tray;
    final angle = fanAngle(chip.slot, chip.slots, spec);
    final y = fanY(chip.slot, chip.slots, spec);
    final shake = shakeOffset(chip.seat, now, spec);
    final exit = chip.exit;

    if (exit == null) {
      final pop = _pop(chip, now, spec);
      final sel = selectAmount(chip, now, spec);
      final swell = promptSwell(chip.seat, now, spec);
      return ChipPose(
        x: _slideX(chip, now, spec) + shake,
        y: y,
        angle: angle,
        scale: pop.scale * (1 + (tray.selectedScale - 1) * sel) * (1 + swell),
        opacity: pop.opacity,
        select: sel,
      );
    }

    final total = _exitTotalMs(chip, spec);
    final since = now - chip.exitMs;
    if (since >= total) {
      return null;
    }
    final lift = 1 + (tray.selectedScale - 1) * chip.exitSelect;

    if (spec.reducedMotion) {
      return ChipPose(
        x: chip.exitX,
        y: y,
        angle: angle,
        scale: lift,
        opacity: 1 - clamp01(since / spec.reducedFadeMs),
        select: chip.exitSelect,
      );
    }

    switch (exit) {
      case ChipExit.spend:
        final u = clamp01(since / tray.spendMs);
        final dissolve = clamp01(
          (u - tray.spendDissolveFrom) / (1 - tray.spendDissolveFrom),
        );
        final shrink = lift + (tray.spendEndScale - lift) * easeInOutCubic(u);
        return ChipPose(
          x: chip.exitX,
          y: y,
          angle: angle,
          scale: shrink * (1 + tray.spendArc * arc(u, 1)),
          opacity: 1 - dissolve,
          select: chip.exitSelect * (1 - u),
          flight: easeInOutCubic(u),
          target: chip.target,
        );
      case ChipExit.wipe:
        final t = since - chip.exitOrder * tray.wipeStaggerMs;
        if (t < 0) {
          return ChipPose(
            x: chip.exitX,
            y: y,
            angle: angle,
            scale: lift,
            opacity: 1,
            select: chip.exitSelect,
          );
        }
        final u = clamp01(t / tray.wipeMs);
        const split = 0.55;
        if (u < split) {
          final k = u / split;
          return ChipPose(
            x: chip.exitX +
                tray.wipeShake *
                    dampedSine(k, cycles: 4, decay: 1.5) *
                    (1 - k * 0.3),
            y: y,
            angle: angle,
            scale: lift,
            opacity: 1,
            select: chip.exitSelect,
          );
        }
        final k = (u - split) / (1 - split);
        return ChipPose(
          x: chip.exitX,
          y: y,
          angle: angle,
          scale: lift + (tray.wipeEndScale - lift) * easeOutCubic(k),
          opacity: 1 - k,
          select: chip.exitSelect * (1 - k),
        );
      case ChipExit.revert:
        final t = since - chip.exitOrder * tray.revertStaggerMs;
        final u = clamp01(t / tray.revertMs);
        return ChipPose(
          x: chip.exitX,
          y: y,
          angle: angle,
          scale: lift + (tray.revertEndScale - lift) * easeInOutCubic(u),
          opacity: 1 - easeInOutCubic(u),
          select: chip.exitSelect * (1 - u),
        );
    }
  }

  ({double scale, double opacity}) _pop(
    TrayChip chip,
    double now,
    MotionSpec spec,
  ) {
    final u = (now - chip.bornMs) /
        (spec.reducedMotion ? spec.reducedFadeMs : spec.tray.popMs);
    if (spec.reducedMotion) {
      return (scale: 1, opacity: clamp01(u));
    }
    final k = clamp01(u);
    return (
      scale: spec.tray.popFromScale +
          (1 - spec.tray.popFromScale) * easeOutBack(k),
      opacity: clamp01(u * 3),
    );
  }
}
