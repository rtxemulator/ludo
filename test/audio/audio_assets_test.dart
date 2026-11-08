import 'dart:io';
import 'dart:typed_data';

import 'package:ludo/ui/core/sfx.dart';
import 'package:test/test.dart';

/// The generated sounds (tool/audio/generate.py -> app/assets/audio/). They
/// are committed build output, so this keeps them honest: every event has a
/// file, the folder stays under the 600 KB cap, every file is Ogg Opus of
/// the expected shape and length, and the app registers the folder.
const int budgetBytes = 600 * 1024;

/// Expected length window per effect (ms), from docs/ludo-sound-themes.md
/// section 2. The dice throw covers the flight (420 ms); the dice roll runs
/// from the first impact to the settle click (about 500 ms).
const Map<SfxEvent, (int, int)> windowsMs = {
  SfxEvent.diceThrow: (300, 520),
  SfxEvent.diceRoll: (380, 600),
  SfxEvent.diceSettle: (60, 130),
  SfxEvent.hop: (40, 100),
  SfxEvent.land: (80, 160),
  SfxEvent.capture: (280, 420),
  SfxEvent.home: (400, 600),
  SfxEvent.six: (200, 320),
  SfxEvent.win: (1500, 2100),
  SfxEvent.illegal: (120, 200),
  SfxEvent.select: (25, 60),
};

class _Opus {
  _Opus(this.channels, this.preSkip, this.durationMs);

  final int channels;
  final int preSkip;
  final double durationMs;

  /// Reads an Ogg Opus file: the OpusHead of the first page and the granule
  /// position of the last page (samples at 48 kHz, pre-skip included).
  static _Opus parse(Uint8List bytes) {
    String tag(int at, int n) =>
        String.fromCharCodes(bytes.sublist(at, at + n));
    expect(tag(0, 4), 'OggS', reason: 'not an Ogg file');
    final segments = bytes[26];
    final head = 27 + segments;
    expect(tag(head, 8), 'OpusHead', reason: 'not Opus');
    final data = ByteData.sublistView(bytes);
    final channels = bytes[head + 9];
    final preSkip = data.getUint16(head + 10, Endian.little);
    var last = -1;
    for (var i = bytes.length - 4; i >= 0; i--) {
      if (bytes[i] == 0x4f && tag(i, 4) == 'OggS') {
        last = i;
        break;
      }
    }
    expect(last, greaterThan(0), reason: 'no last page');
    final granule = data.getInt64(last + 6, Endian.little);
    return _Opus(channels, preSkip, (granule - preSkip) * 1000 / 48000);
  }
}

void main() {
  final dir = Directory('app/assets/audio');

  test('the audio folder exists and holds only Ogg Opus files', () {
    expect(dir.existsSync(), isTrue, reason: 'run tool/audio/generate.py');
    final names = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(names, {...SfxEvent.values.map(sfxAssetFile), musicAssetFile});
  });

  test('every SfxEvent has a file, and the music loop is there', () {
    for (final e in SfxEvent.values) {
      final f = File('${dir.path}/${sfxAssetFile(e)}');
      expect(f.existsSync(), isTrue, reason: '$e -> ${f.path}');
      expect(f.lengthSync(), greaterThan(0), reason: '$e is empty');
    }
    expect(File('${dir.path}/$musicAssetFile').existsSync(), isTrue);
  });

  test('all sound assets together stay under 600 KB', () {
    final total = dir
        .listSync(recursive: true)
        .whereType<File>()
        .fold<int>(0, (sum, f) => sum + f.lengthSync());
    expect(total, lessThanOrEqualTo(budgetBytes), reason: '$total bytes');
  });

  for (final e in SfxEvent.values) {
    test('$e is a mono Ogg Opus sound of the expected length', () {
      final opus =
          _Opus.parse(File('${dir.path}/${sfxAssetFile(e)}').readAsBytesSync());
      final (lo, hi) = windowsMs[e]!;
      expect(opus.channels, 1);
      expect(opus.durationMs, inInclusiveRange(lo, hi));
    });
  }

  test('the music loop is stereo and 60 to 120 seconds long', () {
    final opus =
        _Opus.parse(File('${dir.path}/$musicAssetFile').readAsBytesSync());
    expect(opus.channels, 2);
    expect(opus.durationMs, inInclusiveRange(60000, 120000));
  });

  test('app/pubspec.yaml registers the audio folder as an asset', () {
    final pubspec = File('app/pubspec.yaml').readAsStringSync();
    final assets =
        RegExp(r'^\s*assets:\s*\n((?:\s+-\s+\S+\n?)+)', multiLine: true)
            .firstMatch(pubspec);
    expect(assets, isNotNull, reason: 'no assets: list');
    expect(assets!.group(1), contains('assets/audio/'));
  });
}
