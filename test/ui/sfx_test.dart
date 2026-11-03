import 'dart:io';

import 'package:ludo/ui/core/haptics.dart';
import 'package:ludo/ui/core/sfx.dart';
import 'package:test/test.dart';

/// A player on a fake clock whose scheduled actions run when [advance] says.
class _Rig {
  _Rig({int seed = 1, Map<SfxEvent, double>? minGapMs}) {
    player = SfxPlayer(
      emit: cues.add,
      schedule: (delay, action) => _pending.add((now + delay, action)),
      nowMs: () => now,
      seed: seed,
      minGapMs: minGapMs ?? sfxMinGapMs,
    );
  }

  late final SfxPlayer player;
  final List<SfxCue> cues = [];
  final List<(double, void Function())> _pending = [];
  double now = 0;

  void advance(double ms) {
    now += ms;
    final due = _pending.where((p) => p.$1 <= now).toList();
    _pending.removeWhere((p) => p.$1 <= now);
    for (final p in due) {
      p.$2();
    }
  }
}

void main() {
  group('sfxFor', () {
    test('every haptic event has a sound', () {
      for (final h in HapticEvent.values) {
        expect(() => sfxFor(h), returnsNormally, reason: '$h');
      }
    });

    test('the haptic table maps to the catalogue', () {
      expect(sfxFor(HapticEvent.diceImpact), SfxEvent.diceRoll);
      expect(sfxFor(HapticEvent.diceSettle), SfxEvent.diceSettle);
      expect(sfxFor(HapticEvent.tokenLand), SfxEvent.land);
      expect(sfxFor(HapticEvent.capture), SfxEvent.capture);
      expect(sfxFor(HapticEvent.home), SfxEvent.home);
      expect(sfxFor(HapticEvent.six), SfxEvent.six);
      expect(sfxFor(HapticEvent.win), SfxEvent.win);
      expect(sfxFor(HapticEvent.select), SfxEvent.select);
    });

    test('illegal and no-move share one sound', () {
      expect(sfxFor(HapticEvent.illegal), SfxEvent.illegal);
      expect(sfxFor(HapticEvent.noMove), SfxEvent.illegal);
    });

    test('hop is the only sound without a haptic', () {
      final fromHaptics = HapticEvent.values.map(sfxFor).toSet();
      expect(fromHaptics, isNot(contains(SfxEvent.hop)));
      expect({...fromHaptics, SfxEvent.hop}, SfxEvent.values.toSet());
    });
  });

  group('tables', () {
    test('every event has a gap and a variation', () {
      for (final e in SfxEvent.values) {
        expect(sfxMinGapMs[e], isNotNull, reason: '$e gap');
        expect(sfxMinGapMs[e]!, greaterThan(0), reason: '$e gap');
        expect(sfxVariation[e], isNotNull, reason: '$e variation');
        expect(sfxVariation[e]!.pitch, inInclusiveRange(0, 0.1));
        expect(sfxVariation[e]!.gain, inInclusiveRange(0, 0.15));
      }
    });

    test('only six is delayed, and it follows the settle like its haptic', () {
      expect(sfxDelayMs.keys, [SfxEvent.six]);
      expect(sfxDelayMs[SfxEvent.six],
          hapticPatterns[HapticEvent.six]!.first.afterMs);
    });
  });

  group('clampVolume', () {
    test('keeps 0..1, clamps the rest, NaN is silent', () {
      expect(clampVolume(0.5), 0.5);
      expect(clampVolume(0), 0);
      expect(clampVolume(1), 1);
      expect(clampVolume(-3), 0);
      expect(clampVolume(7), 1);
      expect(clampVolume(double.infinity), 1);
      expect(clampVolume(double.negativeInfinity), 0);
      expect(clampVolume(double.nan), 0);
    });

    test('the player clamps its volume', () {
      final rig = _Rig();
      rig.player.volume = 4;
      expect(rig.player.volume, 1);
      rig.player.volume = -1;
      expect(rig.player.volume, 0);
      rig.player.volume = double.nan;
      expect(rig.player.volume, 0);
    });
  });

  group('SfxPlayer', () {
    test('plays a cue with the event, a volume and a rate', () {
      final rig = _Rig()..player.volume = 0.8;
      rig.player.play(SfxEvent.capture);
      expect(rig.cues, hasLength(1));
      expect(rig.cues.single.event, SfxEvent.capture);
      expect(rig.cues.single.volume, inInclusiveRange(0, 1));
      expect(rig.cues.single.rate, closeTo(1, 0.1));
    });

    test('disabled plays nothing, including delayed cues', () {
      final rig = _Rig()..player.enabled = false;
      for (final e in SfxEvent.values) {
        rig.player.play(e);
      }
      rig.advance(1000);
      expect(rig.cues, isEmpty);
    });

    test('a volume of 0 plays nothing', () {
      final rig = _Rig()..player.volume = 0;
      rig.player.play(SfxEvent.win);
      expect(rig.cues, isEmpty);
    });

    test('a delayed cue is re-checked when it fires', () {
      final rig = _Rig();
      rig.player.play(SfxEvent.six);
      expect(rig.cues, isEmpty);
      rig.player.enabled = false;
      rig.advance(100);
      expect(rig.cues, isEmpty);

      rig.player.enabled = true;
      rig.player.play(SfxEvent.six);
      rig.advance(79);
      expect(rig.cues, isEmpty);
      rig.advance(2);
      expect(rig.cues.map((c) => c.event), [SfxEvent.six]);
    });

    test('the rate limit is per event', () {
      final rig = _Rig();
      rig.player.play(SfxEvent.land);
      rig.advance(10);
      rig.player.play(SfxEvent.land); // too soon
      rig.player.play(SfxEvent.select); // another event, allowed
      expect(rig.cues.map((c) => c.event), [SfxEvent.land, SfxEvent.select]);

      rig.advance(sfxMinGapMs[SfxEvent.land]!);
      rig.player.play(SfxEvent.land);
      expect(rig.cues.map((c) => c.event),
          [SfxEvent.land, SfxEvent.select, SfxEvent.land]);
    });

    test('a refused play does not extend the window', () {
      final rig = _Rig(minGapMs: {for (final e in SfxEvent.values) e: 100});
      rig.player.play(SfxEvent.hop); // t = 0
      rig.advance(60);
      rig.player.play(SfxEvent.hop); // refused
      rig.advance(45);
      rig.player.play(SfxEvent.hop); // t = 105, allowed
      expect(rig.cues, hasLength(2));
    });

    test('reset forgets the rate-limit history', () {
      final rig = _Rig();
      rig.player.play(SfxEvent.win);
      rig.player.play(SfxEvent.win);
      expect(rig.cues, hasLength(1));
      rig.player.reset();
      rig.player.play(SfxEvent.win);
      expect(rig.cues, hasLength(2));
    });

    test('playHaptic plays the mapped sound', () {
      final rig = _Rig();
      rig.player.playHaptic(HapticEvent.noMove);
      expect(rig.cues.single.event, SfxEvent.illegal);
    });
  });

  group('variation', () {
    test('stays inside the spread and the volume stays in 0..1', () {
      final rig = _Rig(seed: 7)..player.volume = 0.95;
      for (var i = 0; i < 400; i++) {
        for (final e in SfxEvent.values) {
          rig.advance(5000);
          rig.player.play(e);
        }
      }
      rig.advance(1000);
      expect(rig.cues, hasLength(400 * SfxEvent.values.length));
      for (final cue in rig.cues) {
        final spread = sfxVariation[cue.event]!;
        expect(cue.rate, inInclusiveRange(1 - spread.pitch, 1 + spread.pitch));
        expect(cue.volume, inInclusiveRange(0, 1));
        expect(
            cue.volume, inInclusiveRange(0.95 * (1 - spread.gain) - 1e-9, 1.0));
      }
    });

    test('an event with no spread is never varied', () {
      final rig = _Rig(seed: 3)..player.volume = 0.6;
      for (var i = 0; i < 20; i++) {
        rig.advance(5000);
        rig.player.play(SfxEvent.win);
      }
      for (final cue in rig.cues) {
        expect(cue.rate, 1);
        expect(cue.volume, closeTo(0.6, 1e-12));
      }
    });

    test('the same seed gives the same cues, another seed other ones', () {
      List<SfxCue> run(int seed) {
        final rig = _Rig(seed: seed);
        for (var i = 0; i < 30; i++) {
          rig.advance(1000);
          rig.player.play(SfxEvent.hop);
        }
        return rig.cues;
      }

      String key(List<SfxCue> cues) =>
          cues.map((c) => '${c.volume}/${c.rate}').join(',');
      expect(key(run(5)), key(run(5)));
      expect(key(run(5)), isNot(key(run(6))));
    });

    test('actually varies a varied event', () {
      final rig = _Rig(seed: 9);
      for (var i = 0; i < 30; i++) {
        rig.advance(1000);
        rig.player.play(SfxEvent.land);
      }
      expect(rig.cues.map((c) => c.rate).toSet().length, greaterThan(10));
    });
  });

  test('the sound core never reads the game dice or generator state', () {
    final source = File('lib/ui/core/sfx.dart').readAsStringSync();
    // Strip comments: the library doc names rngState to say it is not used.
    final code = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('rngState'), isFalse);
    expect(code.contains('Dice'), isFalse);
    expect(code.contains('engine'), isFalse);
  });
}
