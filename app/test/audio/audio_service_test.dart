import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/ui/core/haptics.dart';
import 'package:ludo/ui/core/sfx.dart';

import 'package:ludo_app/audio/audio_service.dart';
import 'package:ludo_app/settings/game_settings.dart';

import '../fakes/fake_audio.dart';

class _Rig {
  _Rig() {
    service = AudioService(
      backend: backend,
      clock: clock,
      observeLifecycle: false,
    );
  }

  final backend = FakeAudioBackend();
  final clock = FakeAudioClock();
  late final AudioService service;

  Future<void> start() async {
    await service.start();
  }

  /// The music volume the table settles on at the default slider value.
  static const double fullMusic = defaultMusicVolume * musicGainBelowEffects;
}

void main() {
  late List<String> logs;
  late DebugPrintCallback oldDebugPrint;

  setUp(() {
    logs = [];
    oldDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
  });
  tearDown(() => debugPrint = oldDebugPrint);

  group('lazy start', () {
    test('building the service touches nothing', () {
      final rig = _Rig();
      expect(rig.backend.initCalls, 0);
      expect(rig.service.ready, isFalse);
      rig.service.play(SfxEvent.land);
      rig.service.enterMusicScreen();
      expect(rig.backend.initCalls, 0);
      expect(rig.backend.effects, isEmpty);
    });

    test('start inits once and loads every effect and the music once',
        () async {
      final rig = _Rig();
      await rig.start();
      await rig.start();
      expect(rig.backend.initCalls, 1);
      expect(rig.service.ready, isTrue);
      expect(rig.backend.loadedEffects.keys.toSet(), SfxEvent.values.toSet());
      expect(
        rig.backend.loadedEffects[SfxEvent.diceRoll],
        'assets/audio/diceRoll.opus',
      );
      expect(rig.backend.loadedMusic, 'assets/audio/music.opus');
    });

    test('sounds asked for before it is ready are dropped, not queued',
        () async {
      final rig = _Rig();
      rig.backend.initGate = Completer<void>();
      final starting = rig.service.start();
      rig.service.play(SfxEvent.land);
      rig.service.play(SfxEvent.select);
      rig.backend.initGate!.complete();
      await starting;
      rig.clock.advance(1000);
      expect(rig.service.ready, isTrue);
      expect(rig.backend.effects, isEmpty);

      rig.service.play(SfxEvent.land);
      expect(rig.backend.effects.single.event, SfxEvent.land);
    });
  });

  group('failure turns audio off for the session', () {
    test('an init error is logged and nothing else happens', () async {
      final rig = _Rig()..backend.failInit = true;
      await rig.start();
      expect(rig.service.failed, isTrue);
      expect(rig.service.ready, isFalse);
      expect(logs.single, contains('Audio off'));
      expect(rig.backend.disposeCalls, 1);

      rig.service.play(SfxEvent.land);
      rig.service.enterMusicScreen();
      rig.service.musicEnabled = true;
      rig.clock.advance(1000);
      expect(rig.backend.effects, isEmpty);
      expect(rig.backend.startMusicCalls, 0);
      // A second start does not try again.
      await rig.start();
      expect(rig.backend.initCalls, 1);
    });

    test('a load error does the same', () async {
      final rig = _Rig()..backend.failLoad = true;
      await rig.start();
      expect(rig.service.failed, isTrue);
      expect(rig.service.ready, isFalse);
      expect(logs, hasLength(1));
    });

    test('an error while playing silences everything after it', () async {
      final rig = _Rig();
      await rig.start();
      rig.backend.failPlay = true;
      rig.service.play(SfxEvent.land); // must not throw
      expect(rig.service.failed, isTrue);
      expect(rig.backend.disposeCalls, 1);
      rig.backend.failPlay = false;
      rig.service.play(SfxEvent.select);
      expect(rig.backend.effects, isEmpty);
    });

    test('an error in the music stops the music and the effects', () async {
      final rig = _Rig();
      await rig.start();
      rig.service.musicEnabled = true;
      rig.backend.failMusic = true;
      rig.service.enterMusicScreen(); // must not throw
      expect(rig.service.failed, isTrue);
      rig.service.play(SfxEvent.land);
      expect(rig.backend.effects, isEmpty);
    });
  });

  group('effects follow the settings live', () {
    test('volume and the switch apply to the next sound', () async {
      final rig = _Rig();
      await rig.start();
      rig.service.sfxVolume = 1;
      rig.service.play(SfxEvent.land);
      final loud = rig.backend.effects.last.volume;

      rig.service.sfxVolume = 0.25;
      rig.clock.advance(500);
      rig.service.play(SfxEvent.land);
      final quiet = rig.backend.effects.last.volume;
      expect(quiet, lessThan(loud / 2));
      expect(rig.backend.effects.last.rate, closeTo(1, 0.1));

      rig.service.sfxEnabled = false;
      rig.clock.advance(500);
      rig.service.play(SfxEvent.land);
      expect(rig.backend.effects, hasLength(2));

      rig.service.sfxEnabled = true;
      rig.service.play(SfxEvent.land);
      expect(rig.backend.effects, hasLength(3));

      rig.service.sfxVolume = 0;
      rig.clock.advance(500);
      rig.service.play(SfxEvent.land);
      expect(rig.backend.effects, hasLength(3));
    });

    test('the six chime waits for its delay, then plays', () async {
      final rig = _Rig();
      await rig.start();
      rig.service.play(SfxEvent.six);
      expect(rig.backend.effects, isEmpty);
      rig.clock.advance(200);
      expect(rig.backend.effects.single.event, SfxEvent.six);
    });

    test('cancelPending drops a delayed cue', () async {
      final rig = _Rig();
      await rig.start();
      rig.service.play(SfxEvent.six);
      rig.service.cancelPending();
      rig.clock.advance(500);
      expect(rig.backend.effects, isEmpty);
    });

    test('a haptic event plays its sound', () async {
      final rig = _Rig();
      await rig.start();
      rig.service.playHaptic(HapticEvent.tokenLand);
      expect(rig.backend.effects.single.event, SfxEvent.land);
    });
  });

  group('music', () {
    Future<_Rig> ready({bool musicOn = true}) async {
      final rig = _Rig();
      await rig.start();
      rig.service.musicEnabled = musicOn;
      return rig;
    }

    test('stays silent until a table or replay screen is up', () async {
      final rig = await ready();
      rig.clock.advance(1000);
      expect(rig.backend.startMusicCalls, 0);
      rig.service.enterMusicScreen();
      expect(rig.backend.startMusicCalls, 1);
    });

    test('stays silent while the setting is off', () async {
      final rig = await ready(musicOn: false);
      rig.service.enterMusicScreen();
      rig.clock.advance(1000);
      expect(rig.backend.startMusicCalls, 0);
      rig.service.musicEnabled = true; // live
      expect(rig.backend.startMusicCalls, 1);
    });

    test('fades in over 400 ms, linearly, and ends at the slider level',
        () async {
      final rig = await ready();
      rig.service.enterMusicScreen();
      expect(rig.backend.musicVolumes.first, 0);
      rig.clock.advance(200);
      expect(rig.backend.lastMusicVolume, closeTo(_Rig.fullMusic / 2, 0.01));
      rig.clock.advance(250);
      expect(rig.backend.lastMusicVolume, closeTo(_Rig.fullMusic, 1e-9));
      expect(rig.clock.activeTickers, 0, reason: 'the ticker stops');
    });

    test('plays about 6 dB below the effects at the same slider value',
        () async {
      final rig = await ready();
      rig.service.musicVolume = 1;
      rig.service.sfxVolume = 1;
      rig.service.enterMusicScreen();
      rig.clock.advance(500);
      expect(rig.backend.lastMusicVolume, closeTo(0.5, 0.01));
    });

    test('fades out over 400 ms when the last screen leaves, then pauses',
        () async {
      final rig = await ready();
      rig.service.enterMusicScreen();
      rig.clock.advance(500);
      rig.service.leaveMusicScreen();
      expect(rig.backend.musicPlaying, isTrue);
      rig.clock.advance(200);
      expect(rig.backend.lastMusicVolume, closeTo(_Rig.fullMusic / 2, 0.01));
      expect(rig.backend.musicPlaying, isTrue);
      rig.clock.advance(250);
      expect(rig.backend.lastMusicVolume, 0);
      expect(rig.backend.musicPlaying, isFalse);
      expect(rig.service.musicRunning, isFalse);
      expect(rig.clock.activeTickers, 0);
    });

    test('a second screen over the first keeps the music going', () async {
      final rig = await ready();
      rig.service.enterMusicScreen(); // the table
      rig.clock.advance(500);
      rig.service.enterMusicScreen(); // the replay on top
      rig.service.leaveMusicScreen();
      rig.clock.advance(1000);
      expect(rig.backend.musicPlaying, isTrue);
      expect(rig.backend.lastMusicVolume, closeTo(_Rig.fullMusic, 1e-9));
      expect(rig.backend.pauseMusicCalls, 0);
    });

    test('coming back during a fade-out continues from where it was', () async {
      final rig = await ready();
      rig.service.enterMusicScreen();
      rig.clock.advance(500);
      rig.service.leaveMusicScreen();
      rig.clock.advance(200);
      rig.service.enterMusicScreen();
      expect(rig.backend.startMusicCalls, 1, reason: 'never paused');
      rig.clock.advance(500);
      expect(rig.backend.lastMusicVolume, closeTo(_Rig.fullMusic, 1e-9));
      expect(rig.backend.musicPlaying, isTrue);
    });

    test('the slider applies live while playing', () async {
      final rig = await ready();
      rig.service.enterMusicScreen();
      rig.clock.advance(500);
      rig.service.musicVolume = 1;
      expect(rig.backend.lastMusicVolume, closeTo(0.5, 1e-9));
      rig.service.musicVolume = 0.2;
      expect(rig.backend.lastMusicVolume, closeTo(0.1, 1e-9));
    });

    test('switching it off fades out and pauses', () async {
      final rig = await ready();
      rig.service.enterMusicScreen();
      rig.clock.advance(500);
      rig.service.musicEnabled = false;
      rig.clock.advance(500);
      expect(rig.backend.musicPlaying, isFalse);
    });

    test(
        'a screen entered before the service is ready starts the music '
        'once it is', () async {
      final rig = _Rig();
      rig.service.musicEnabled = true;
      rig.service.enterMusicScreen();
      expect(rig.backend.startMusicCalls, 0);
      await rig.start();
      expect(rig.backend.startMusicCalls, 1);
    });
  });

  group('lifecycle', () {
    test('leaving resumed pauses the music at once; returning fades it in',
        () async {
      final rig = _Rig();
      await rig.start();
      rig.service.musicEnabled = true;
      rig.service.enterMusicScreen();
      rig.clock.advance(500);

      rig.service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(rig.backend.musicPlaying, isFalse);
      expect(rig.backend.pauseMusicCalls, 1);
      expect(rig.clock.activeTickers, 0);

      rig.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(rig.backend.musicPlaying, isTrue);
      expect(rig.backend.lastMusicVolume, 0, reason: 'starts from silence');
      rig.clock.advance(200);
      expect(rig.backend.lastMusicVolume, closeTo(_Rig.fullMusic / 2, 0.01));
      rig.clock.advance(250);
      expect(rig.backend.lastMusicVolume, closeTo(_Rig.fullMusic, 1e-9));
    });

    test('inactive and hidden count as leaving resumed', () async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden
      ]) {
        final rig = _Rig();
        await rig.start();
        rig.service.musicEnabled = true;
        rig.service.enterMusicScreen();
        rig.clock.advance(500);
        rig.service.didChangeAppLifecycleState(state);
        expect(rig.backend.musicPlaying, isFalse, reason: '$state');
      }
    });

    test('effects are never queued across a pause', () async {
      final rig = _Rig();
      await rig.start();
      rig.service.play(SfxEvent.six); // waiting for its delay
      rig.service.didChangeAppLifecycleState(AppLifecycleState.paused);
      rig.service.play(SfxEvent.land); // asked for while paused
      rig.clock.advance(1000);
      rig.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      rig.clock.advance(1000);
      expect(rig.backend.effects, isEmpty);

      rig.service.play(SfxEvent.land);
      expect(rig.backend.effects.single.event, SfxEvent.land);
    });

    test('music that was off stays off after a pause and resume', () async {
      final rig = _Rig();
      await rig.start();
      rig.service.enterMusicScreen();
      rig.service.didChangeAppLifecycleState(AppLifecycleState.paused);
      rig.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      rig.clock.advance(1000);
      expect(rig.backend.startMusicCalls, 0);
    });
  });

  group('bind', () {
    test('applies the four settings now and whenever they change', () async {
      final rig = _Rig();
      await rig.start();
      final settings = GameSettings(
        sfxEnabled: false,
        sfxVolume: 0.3,
        musicEnabled: true,
        musicVolume: 0.6,
      );
      final unbind = rig.service.bind(settings);
      expect(rig.service.sfxEnabled, isFalse);
      expect(rig.service.sfxVolume, closeTo(0.3, 1e-9));
      expect(rig.service.musicEnabled, isTrue);
      expect(rig.service.musicVolume, closeTo(0.6, 1e-9));

      settings.sfxEnabled = true;
      settings.sfxVolume = 0.9;
      settings.musicEnabled = false;
      settings.musicVolume = 0.1;
      expect(rig.service.sfxEnabled, isTrue);
      expect(rig.service.sfxVolume, closeTo(0.9, 1e-9));
      expect(rig.service.musicEnabled, isFalse);
      expect(rig.service.musicVolume, closeTo(0.1, 1e-9));

      unbind();
      settings.sfxVolume = 0.5;
      expect(rig.service.sfxVolume, closeTo(0.9, 1e-9));
    });
  });
}
