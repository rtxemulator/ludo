import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ludo/ui/core/sfx.dart';

import 'audio_backend.dart';

/// [AudioBackend] on `flutter_soloud`: the effects are decoded into memory
/// once and played with a rate; the music loop streams from disk.
///
/// Only `main.dart` imports this file, so the tests never load the plugin.
class SoloudBackend implements AudioBackend {
  SoloudBackend({SoLoud? engine}) : _engine = engine ?? SoLoud.instance;

  final SoLoud _engine;
  final Map<SfxEvent, AudioSource> _effects = {};
  AudioSource? _music;
  SoundHandle? _musicHandle;

  @override
  Future<void> init() => _engine.init(sampleRate: 48000, bufferSize: 1024);

  @override
  Future<void> loadEffect(SfxEvent event, String asset) async {
    _effects[event] = await _engine.loadAsset(asset);
  }

  @override
  Future<void> loadMusic(String asset) async {
    _music = await _engine.loadAsset(asset, mode: LoadMode.disk);
  }

  @override
  void playEffect(
    SfxEvent event, {
    required double volume,
    required double rate,
  }) {
    final source = _effects[event];
    if (source == null) {
      return;
    }
    _engine.play(source, volume: volume, scale: rate);
  }

  @override
  void startMusic(double volume) {
    final handle = _musicHandle;
    if (handle != null) {
      _engine.setVolume(handle, volume);
      _engine.setPause(handle, false);
      return;
    }
    final source = _music;
    if (source == null) {
      return;
    }
    final started = _engine.play(source, volume: volume, looping: true);
    // The music must never be the voice that is dropped when many effects
    // play at once.
    _engine.setProtectVoice(started, true);
    _musicHandle = started;
  }

  @override
  void setMusicVolume(double volume) {
    final handle = _musicHandle;
    if (handle != null) {
      _engine.setVolume(handle, volume);
    }
  }

  @override
  void pauseMusic() {
    final handle = _musicHandle;
    if (handle != null) {
      _engine.setPause(handle, true);
    }
  }

  @override
  Future<void> dispose() async {
    _musicHandle = null;
    _music = null;
    _effects.clear();
    _engine.deinit();
  }
}
