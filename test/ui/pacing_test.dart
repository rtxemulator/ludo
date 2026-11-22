import 'dart:io';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/ui/core/dice3d.dart';
import 'package:ludo/ui/core/fx_scene.dart';
import 'package:ludo/ui/core/motion_spec.dart';
import 'package:ludo/ui/core/move_plan.dart';
import 'package:ludo/ui/core/pacing.dart';
import 'package:test/test.dart';

import '../engine/helpers.dart';

void main() {
  group('AnimationQueue', () {
    test('beats run one after another, never at the same time', () {
      final q = AnimationQueue();
      final roll = q.add(BeatKind.roll, 920, 1000)!;
      final reveal = q.add(BeatKind.reveal, 200, 1000)!;
      final move = q.add(BeatKind.move, 500, 1100)!;
      expect(roll.startMs, 1000);
      expect(roll.endMs, 1920);
      expect(reveal.startMs, roll.endMs);
      expect(move.startMs, reveal.endMs);
      expect(q.freeAtMs(1100), move.endMs);
      // No two beats overlap.
      final beats = q.pending(1000);
      for (var i = 1; i < beats.length; i++) {
        expect(beats[i].startMs, greaterThanOrEqualTo(beats[i - 1].endMs));
      }
    });

    test('a beat added to an idle queue starts now, not in the past', () {
      final q = AnimationQueue();
      q.add(BeatKind.move, 300, 0);
      final late = q.add(BeatKind.hold, 600, 5000)!;
      expect(late.startMs, 5000);
    });

    test('busy until the last beat ends, then free', () {
      final q = AnimationQueue();
      q.add(BeatKind.roll, 100, 0);
      q.add(BeatKind.tail, 100, 0);
      expect(q.busy(0), isTrue);
      expect(q.busy(199), isTrue);
      expect(q.busy(200), isFalse);
      expect(q.remainingMs(50), 150);
      expect(q.remainingMs(500), 0);
    });

    test('current names the running beat', () {
      final q = AnimationQueue();
      q.add(BeatKind.roll, 100, 0);
      q.add(BeatKind.hold, 100, 0);
      expect(q.current(50)!.kind, BeatKind.roll);
      expect(q.current(150)!.kind, BeatKind.hold);
      expect(q.current(250), isNull);
    });

    test('skip ends everything and says how far to move the clock', () {
      final q = AnimationQueue();
      q.add(BeatKind.roll, 920, 0);
      q.add(BeatKind.hold, 600, 0);
      expect(q.skip(300), 1520 - 300);
      expect(q.busy(300), isFalse);
      expect(q.skip(300), 0);
    });

    test('empty and zero-length beats add nothing', () {
      final q = AnimationQueue();
      expect(q.add(BeatKind.tail, 0, 0), isNull);
      expect(q.add(BeatKind.tail, -5, 0), isNull);
      expect(q.length, 0);
      expect(q.busy(0), isFalse);
    });

    test('finished beats are forgotten when the next one is added', () {
      final q = AnimationQueue();
      for (var i = 0; i < 50; i++) {
        q.add(BeatKind.move, 100, i * 1000.0);
      }
      expect(q.length, 1);
    });

    test('clear forgets everything', () {
      final q = AnimationQueue()..add(BeatKind.move, 100, 0);
      q.clear();
      expect(q.busy(0), isFalse);
    });
  });

  group('ThinkDelay', () {
    const standard = MotionSpec.standard;

    test('is always 400..900 ms and not constant', () {
      final think = ThinkDelay(7);
      final seen = <double>{};
      for (var i = 0; i < 300; i++) {
        final ms = think.next(standard);
        expect(ms, inInclusiveRange(400, 900));
        seen.add(ms);
      }
      expect(seen.length, greaterThan(100));
    });

    test('the same seed gives the same delays', () {
      final a = ThinkDelay(3);
      final b = ThinkDelay(3);
      for (var i = 0; i < 20; i++) {
        expect(a.next(standard), b.next(standard));
      }
    });

    test('fast divides it, reduced motion uses its short fixed time', () {
      final fast = standard.scaled(AnimationSpeed.fast.factor);
      final think = ThinkDelay(5);
      for (var i = 0; i < 100; i++) {
        expect(
          think.next(fast),
          inInclusiveRange(400 / 1.6 - 1e-9, 900 / 1.6 + 1e-9),
        );
      }
      expect(ThinkDelay().next(MotionSpec.reduced), Pacing.reducedThinkMs);
    });

    test('the no-move hold is about 600 ms at normal speed', () {
      expect(Pacing.noMoveMs(standard), 600);
      expect(
        Pacing.noMoveMs(standard.scaled(2)),
        closeTo(300, 1e-9),
      );
    });
  });

  group('MotionSpec.scaled', () {
    test('1 returns the same spec', () {
      expect(identical(MotionSpec.standard.scaled(1), MotionSpec.standard),
          isTrue);
    });

    test('durations shrink, distances and idle periods stay', () {
      final f = MotionSpec.standard.scaled(2);
      const s = MotionSpec.standard;
      expect(f.speed, 2);
      expect(f.hopStepMs, s.hopStepMs / 2);
      expect(f.captureReturnMs, s.captureReturnMs / 2);
      expect(f.toastMs, s.toastMs / 2);
      expect(f.dice3d.settleEndMs, s.dice3d.settleEndMs / 2);
      expect(f.dice3d.revealEndMs, s.dice3d.revealEndMs / 2);
      expect(f.tray.spendMs, s.tray.spendMs / 2);
      // Not durations.
      expect(f.hopArc, s.hopArc);
      expect(f.dice3d.flightApex, s.dice3d.flightApex);
      expect(f.sparkCount, s.sparkCount);
      expect(f.maxParticles, s.maxParticles);
      // The waiting state keeps its rhythm.
      expect(f.pulsePeriodMs, s.pulsePeriodMs);
      expect(f.idleBobPeriodMs, s.idleBobPeriodMs);
    });

    test('scaling keeps reduced motion on', () {
      expect(MotionSpec.reduced.scaled(2).reducedMotion, isTrue);
    });

    test('a faster spec really makes the dice and a hop shorter', () {
      const s = MotionSpec.standard;
      final f = s.scaled(1.6);
      final slow = Dice3dTimeline(value: 4, seed: 1, spec: s);
      final fast = Dice3dTimeline(value: 4, seed: 1, spec: f);
      expect(fast.settleMs, closeTo(slow.settleMs / 1.6, 1e-9));
      expect(fast.durationMs, closeTo(slow.durationMs / 1.6, 1e-9));

      final before = makeState(tokens: {
        0: [2, -1, -1, -1],
      }, dice: 3);
      final move = Engine.legalMoves(before).single;
      final after = Engine.apply(before, move);
      final a = MoveAnimationPlan.plan(
          before: before, after: after, move: move, spec: s);
      final b = MoveAnimationPlan.plan(
          before: before, after: after, move: move, spec: f);
      expect(b.totalMs, closeTo(a.totalMs / 1.6, 1e-9));
    });

    test('every duration field of the specs is scaled (or listed as idle)', () {
      // Guard against a new `...Ms` field that scaled() forgets.
      const idle = {'reducedFadeMs', 'pulsePeriodMs', 'idleBobPeriodMs'};
      final source = File('lib/ui/core/motion_spec.dart').readAsStringSync();
      final fields = RegExp(r'final double (\w+Ms);')
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();
      expect(fields, isNotEmpty);
      for (final name in fields) {
        if (idle.contains(name)) {
          expect(source, contains('$name: $name,'), reason: name);
        } else {
          expect(source, contains('$name: $name / factor,'), reason: name);
        }
      }
    });
  });

  group('PlanEffects.endMs', () {
    test('is the end of the last ring, spark or glow', () {
      final before = makeState(tokens: {
        0: [9, -1, -1, -1],
        2: [38, -1, -1, -1],
      }, dice: 3);
      final move = Engine.legalMoves(before).single;
      final after = Engine.apply(before, move);
      final plan = MoveAnimationPlan.plan(
        before: before,
        after: after,
        move: move,
        startMs: 1000,
      );
      var expected = 0.0;
      for (final r in plan.effects.rings) {
        if (r.ring.endMs > expected) {
          expected = r.ring.endMs;
        }
      }
      expect(plan.effects.endMs, expected);
      expect(plan.effects.endMs, greaterThan(1000));
      expect(const PlanEffects().endMs, 0);
    });
  });
}
