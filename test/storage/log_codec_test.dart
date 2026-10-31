import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/storage/storage.dart';
import 'package:test/test.dart';

void main() {
  group('pack / unpack', () {
    test('all 192 valid entries round-trip through one byte', () {
      var count = 0;
      for (var seat = 0; seat < 4; seat++) {
        for (var dice = 1; dice <= 6; dice++) {
          for (var token = 0; token < 4; token++) {
            for (final unit in [false, true]) {
              final entry = MoveLogEntry(
                seat: seat,
                dice: dice,
                tokenIndex: token,
                unit: unit,
              );
              final byte = MoveLogCodec.pack(entry);
              expect(byte, inInclusiveRange(0, 255));
              expect(MoveLogCodec.unpack(byte), entry);
              count++;
            }
          }
        }
      }
      expect(count, 192);
    });

    test('bytes with an impossible die are refused', () {
      for (var byte = 0; byte < 256; byte++) {
        final die = (byte >> 2) & 7;
        expect(MoveLogCodec.unpack(byte) == null, die > 5, reason: '$byte');
      }
      expect(MoveLogCodec.unpack(-1), isNull);
      expect(MoveLogCodec.unpack(256), isNull);
    });

    test('values the engine can never produce are a programming error', () {
      MoveLogEntry e({int seat = 0, int dice = 1, int token = 0}) =>
          MoveLogEntry(seat: seat, dice: dice, tokenIndex: token);
      expect(() => MoveLogCodec.pack(e(seat: 4)), throwsArgumentError);
      expect(() => MoveLogCodec.pack(e(seat: -1)), throwsArgumentError);
      expect(() => MoveLogCodec.pack(e(dice: 0)), throwsArgumentError);
      expect(() => MoveLogCodec.pack(e(dice: 7)), throwsArgumentError);
      expect(() => MoveLogCodec.pack(e(token: 4)), throwsArgumentError);
    });
  });

  group('encode / decode', () {
    const log = [
      MoveLogEntry(seat: 0, dice: 6, tokenIndex: 0),
      MoveLogEntry(seat: 1, dice: 3, tokenIndex: 2, unit: true),
      MoveLogEntry(seat: 3, dice: 1, tokenIndex: 3),
    ];

    test('two lowercase hex digits per entry', () {
      final text = MoveLogCodec.encode(log);
      expect(text.length, 6);
      expect(text, matches(RegExp(r'^[0-9a-f]{6}$')));
      expect(MoveLogCodec.encode(const []), '');
    });

    test('round trip, empty log included', () {
      final back = MoveLogCodec.decode(MoveLogCodec.encode(log));
      expect(back.clean, isTrue);
      expect(back.entries, log);
      expect(MoveLogCodec.decode('').entries, isEmpty);
      expect(MoveLogCodec.decode('').clean, isTrue);
    });

    test('upper case digits are accepted', () {
      final text = MoveLogCodec.encode(log).toUpperCase();
      expect(MoveLogCodec.decode(text).entries, log);
    });

    test('a cut-off string keeps the whole entries before the cut', () {
      final text = MoveLogCodec.encode(log);
      final cut = MoveLogCodec.decode(text.substring(0, text.length - 1));
      expect(cut.clean, isFalse);
      expect(cut.badIndex, 2);
      expect(cut.reason, 'cut off');
      expect(cut.entries, log.take(2).toList());
    });

    test('a bad character stops at its entry', () {
      final text = MoveLogCodec.encode(log);
      final bad = '${text.substring(0, 2)}zz${text.substring(4)}';
      final decoded = MoveLogCodec.decode(bad);
      expect(decoded.badIndex, 1);
      expect(decoded.entries, [log.first]);
    });

    test('sign characters are not hex digits', () {
      expect(MoveLogCodec.decode('-1').badIndex, 0);
      expect(MoveLogCodec.decode('+f').badIndex, 0);
      expect(MoveLogCodec.decode(' 1').badIndex, 0);
      expect(MoveLogCodec.decode('0x').badIndex, 0);
    });

    test('an impossible die stops decoding', () {
      // dice bits 110 = 6 (die 7).
      final decoded = MoveLogCodec.decode('00${(6 << 2).toRadixString(16)}');
      expect(decoded.badIndex, 1);
      expect(decoded.reason, 'impossible entry');
      expect(decoded.entries.length, 1);
    });

    test('non-ASCII text does not throw', () {
      final decoded = MoveLogCodec.decode('é€😀');
      expect(decoded.clean, isFalse);
      expect(decoded.entries, isEmpty);
    });
  });
}
