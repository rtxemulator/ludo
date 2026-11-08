import 'package:ludo/ui/core/music_fade.dart';
import 'package:test/test.dart';

void main() {
  group('MusicFade', () {
    test('starts silent and stays there', () {
      final fade = MusicFade();
      expect(fade.levelAt(0), 0);
      expect(fade.levelAt(5000), 0);
      expect(fade.isFading(0), isFalse);
    });

    test('fades in linearly over 400 ms', () {
      final fade = MusicFade()..fadeTo(1, 1000);
      expect(fade.levelAt(1000), 0);
      expect(fade.levelAt(1100), closeTo(0.25, 1e-9));
      expect(fade.levelAt(1200), closeTo(0.5, 1e-9));
      expect(fade.levelAt(1400), 1);
      expect(fade.levelAt(9000), 1);
      expect(fade.isFading(1399), isTrue);
      expect(fade.isFading(1400), isFalse);
    });

    test('fades out linearly over 400 ms', () {
      final fade = MusicFade(level: 1)..fadeTo(0, 50);
      expect(fade.levelAt(50), 1);
      expect(fade.levelAt(250), closeTo(0.5, 1e-9));
      expect(fade.levelAt(450), 0);
    });

    test('turning back halfway continues from the current level', () {
      final fade = MusicFade()..fadeTo(1, 0);
      expect(fade.levelAt(200), closeTo(0.5, 1e-9));
      fade.fadeTo(0, 200);
      expect(fade.levelAt(200), closeTo(0.5, 1e-9));
      // The rate stays the same, so half a swing takes half the time.
      expect(fade.levelAt(300), closeTo(0.25, 1e-9));
      expect(fade.levelAt(400), 0);
    });

    test('fading to where it is heading changes nothing', () {
      final fade = MusicFade()..fadeTo(1, 0);
      fade.fadeTo(1, 300);
      expect(fade.levelAt(400), 1);
      expect(fade.levelAt(200), closeTo(0.5, 1e-9));
    });

    test('jumpTo sets the level at once', () {
      final fade = MusicFade()..fadeTo(1, 0);
      fade.jumpTo(0);
      expect(fade.levelAt(100), 0);
      expect(fade.target, 0);
      expect(fade.isFading(100), isFalse);
    });

    test('levels outside 0..1 and NaN are clamped', () {
      final fade = MusicFade(level: 3);
      expect(fade.levelAt(0), 1);
      fade.fadeTo(-2, 0);
      expect(fade.target, 0);
      fade.jumpTo(double.nan);
      expect(fade.levelAt(0), 0);
    });

    test('a custom duration scales the fade', () {
      final fade = MusicFade(durationMs: 1000)..fadeTo(1, 0);
      expect(fade.levelAt(500), closeTo(0.5, 1e-9));
      expect(fade.levelAt(1000), 1);
    });
  });
}
