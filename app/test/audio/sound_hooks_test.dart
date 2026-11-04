import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/ui/core/haptics.dart';
import 'package:ludo/ui/core/sfx.dart';

import 'package:ludo_app/audio/audio_service.dart';
import 'package:ludo_app/audio/game_feedback.dart';
import 'package:ludo_app/game/game_controller.dart';
import 'package:ludo_app/game/replay_controller.dart';
import 'package:ludo_app/haptics/haptics_service.dart';

import '../fakes/fake_audio.dart';
import '../save_fixtures.dart';

class _Audio {
  final backend = FakeAudioBackend();
  final clock = FakeAudioClock();
  late final AudioService service = AudioService(
    backend: backend,
    clock: clock,
    observeLifecycle: false,
  );

  static Future<_Audio> ready() async {
    final audio = _Audio();
    await audio.service.start();
    return audio;
  }

  List<SfxEvent> get played => [for (final e in backend.effects) e.event];

  int count(SfxEvent event) => played.where((e) => e == event).length;
}

void main() {
  group('GameFeedback', () {
    late _Audio audio;
    late GameFeedback feedback;

    setUp(() async {
      audio = await _Audio.ready();
      feedback = GameFeedback(
        haptics: HapticsService()..enabled = false,
        audio: audio.service,
      );
    });

    test('a haptic event also plays its sound', () {
      feedback.play(HapticEvent.tokenLand);
      expect(audio.played, [SfxEvent.land]);
    });

    test('sound() plays a sound with no haptic', () {
      feedback.sound(SfxEvent.hop);
      expect(audio.played, [SfxEvent.hop]);
    });

    test('muted plays no sound at all', () {
      feedback.soundMuted = true;
      feedback.play(HapticEvent.capture);
      feedback.sound(SfxEvent.hop);
      expect(audio.played, isEmpty);
      feedback.soundMuted = false;
      feedback.play(HapticEvent.capture);
      expect(audio.played, [SfxEvent.capture]);
    });

    test('muting drops a cue that is still waiting', () {
      feedback.play(HapticEvent.six); // the six chime waits 80 ms
      feedback.soundMuted = true;
      audio.clock.advance(500);
      expect(audio.played, isEmpty);
    });

    test('enabled is the haptics switch only', () {
      expect(feedback.enabled, isFalse);
      feedback.enabled = true;
      expect(feedback.haptics.enabled, isTrue);
      feedback.enabled = false;
      feedback.play(HapticEvent.select);
      expect(audio.played, [SfxEvent.select], reason: 'sound is independent');
    });

    test('without an audio service it is just haptics', () {
      final quiet = GameFeedback(haptics: HapticsService()..enabled = false);
      quiet.play(HapticEvent.win); // must not throw
      quiet.sound(SfxEvent.hop);
      quiet.cancelSounds();
    });
  });

  group('GameController hooks', () {
    /// Plays one full move on a table whose audio shares the frame clock;
    /// returns the plan of that move.
    Future<({GameController game, _Audio audio, int hops})> playAMove({
      bool muted = false,
    }) async {
      final audio = await _Audio.ready();
      var t = 0.0;
      final game = GameController(
        seed: 11,
        now: () => t,
        haptics: false,
        audio: audio.service,
      );
      game.feedback.soundMuted = muted;
      void frame() {
        t += 16;
        audio.clock.advance(16);
        game.tick();
      }

      for (var i = 0; i < 5000 && game.phase != GamePhase.moving; i++) {
        if (game.phase == GamePhase.awaitingRoll) {
          game.roll();
        } else if (game.phase == GamePhase.awaitingMove) {
          final move = game.legal.first;
          game.tapAt(game.resting[move.owner][move.tokenIndex]);
        } else {
          frame();
        }
      }
      expect(game.phase, GamePhase.moving);
      final hops = game.plan!.hopTimesMs.length;
      for (var i = 0; i < 5000 && game.phase == GamePhase.moving; i++) {
        frame();
      }
      return (game: game, audio: audio, hops: hops);
    }

    test('one hop sound per hop step of the move', () async {
      final r = await playAMove();
      expect(r.hops, greaterThan(0));
      expect(r.audio.count(SfxEvent.hop), r.hops);
      expect(r.audio.count(SfxEvent.land), greaterThanOrEqualTo(1));
      r.game.dispose();
    });

    test('the dice and the landing play through the same place', () async {
      final r = await playAMove();
      expect(r.audio.played, contains(SfxEvent.diceRoll));
      expect(r.audio.played, contains(SfxEvent.diceSettle));
      r.game.dispose();
    });

    test('muted effects play nothing, hops included', () async {
      final r = await playAMove(muted: true);
      expect(r.audio.played, isEmpty);
      r.game.dispose();
    });

    test('a controller without audio is unaffected', () {
      var t = 0.0;
      final game = GameController(seed: 7, now: () => t, haptics: false);
      game.roll();
      t = 1000;
      game.tick();
      expect(game.lastRoll, inInclusiveRange(1, 6));
      game.dispose();
    });
  });

  group('replay gating', () {
    late _Audio audio;
    late ReplayController replay;
    var t = 0.0;

    void frame() {
      t += 16;
      audio.clock.advance(16);
      replay.tick();
    }

    void settle() {
      for (var i = 0; i < 4000 && replay.game.replayMoving; i++) {
        frame();
      }
      expect(replay.game.replayMoving, isFalse);
    }

    setUp(() async {
      t = 0;
      audio = await _Audio.ready();
      replay = ReplayController(
        script: ReplayScript.of(
          playSave(id: 'gate', at: day, decisions: 30, seed: 11),
        ),
        clock: () => t,
        haptics: false,
        audio: audio.service,
      );
    });

    tearDown(() => replay.dispose());

    test('1x plays the effects of a step', () {
      expect(replay.speed, 1);
      replay.stepForward();
      settle();
      expect(audio.count(SfxEvent.hop), greaterThan(0));
      expect(audio.count(SfxEvent.land), greaterThan(0));
    });

    test('2x and 4x mute them, back to 1x brings them back', () {
      replay.speed = 2;
      replay.stepForward();
      settle();
      replay.speed = 4;
      replay.stepForward();
      settle();
      expect(audio.played, isEmpty);

      replay.speed = 1;
      replay.stepForward();
      settle();
      expect(audio.played, isNotEmpty);
    });

    test('a scrub or a jump plays nothing', () {
      replay.seek(6);
      replay.toEnd();
      replay.stepBack();
      replay.toStart();
      for (var i = 0; i < 100; i++) {
        frame();
      }
      expect(audio.played, isEmpty);
    });

    test('the music is not touched by the speed', () async {
      audio.service.musicEnabled = true;
      audio.service.enterMusicScreen();
      audio.clock.advance(500);
      replay.speed = 4;
      replay.speed = 2;
      replay.speed = 1;
      audio.clock.advance(500);
      expect(audio.backend.musicPlaying, isTrue);
      expect(audio.backend.pauseMusicCalls, 0);
    });
  });

  group('the audio path stays away from the dice', () {
    test('no file in lib/audio reads rngState or uses Dice', () {
      final files = Directory('lib/audio')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      final banned = RegExp(r'rngState|\bDice\b|dice\.dart');
      for (final f in files) {
        expect(banned.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });
  });
}
