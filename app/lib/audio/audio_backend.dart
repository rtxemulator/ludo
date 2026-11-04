import 'package:ludo/ui/core/sfx.dart';

/// What `AudioService` needs from an audio engine. The real one is
/// `SoloudBackend` (flutter_soloud); tests use a fake.
///
/// Every method may throw: the service treats any error as "audio is off for
/// this session" (docs/ludo-sound-themes.md section 4).
abstract class AudioBackend {
  /// Starts the engine. No audio focus is requested.
  Future<void> init();

  /// Loads the effect for [event] from the bundled [asset] once; it stays
  /// loaded for the whole session.
  Future<void> loadEffect(SfxEvent event, String asset);

  /// Loads the music loop from the bundled [asset] (streamed, not decoded
  /// into memory).
  Future<void> loadMusic(String asset);

  /// Plays the loaded effect once. [volume] is `0..1`, [rate] the playback
  /// speed around 1.
  void playEffect(SfxEvent event,
      {required double volume, required double rate});

  /// Starts the music loop at [volume], or continues it where it was paused.
  void startMusic(double volume);

  /// Sets the volume of the running music (`0..1`).
  void setMusicVolume(double volume);

  /// Pauses the music, keeping its place.
  void pauseMusic();

  /// Releases everything. Never called twice.
  Future<void> dispose();
}
