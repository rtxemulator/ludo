import 'package:ludo/engine/ludo_engine.dart';

/// Result of reading a log string: the entries before the first bad one.
class LogDecode {
  const LogDecode(this.entries, {this.badIndex, this.reason});

  /// The entries that decoded cleanly, in order.
  final List<MoveLogEntry> entries;

  /// Index of the first entry that could not be read, or `null` when the
  /// whole string decoded.
  final int? badIndex;

  /// Why decoding stopped at [badIndex].
  final String? reason;

  /// Whether the whole string decoded.
  bool get clean => badIndex == null;
}

/// Compact text form of a move log: one byte, written as two hex digits, per
/// decision.
///
/// `v = seat | (dice - 1) << 2 | tokenIndex << 5 | unit << 7`
///
/// Seat `0..3` (bits 0-1), die `1..6` stored as `0..5` (bits 2-4), token
/// `0..3` (bits 5-6) and the blockade-unit flag (bit 7). `decode` never
/// throws: it returns the valid prefix and where it stopped.
abstract final class MoveLogCodec {
  /// The byte of [entry]. Throws [ArgumentError] for a value the engine can
  /// never produce (a programming error, not bad input).
  static int pack(MoveLogEntry entry) {
    if (entry.seat < 0 || entry.seat >= seatCount) {
      throw ArgumentError.value(entry.seat, 'seat', 'must be 0..3');
    }
    if (entry.dice < 1 || entry.dice > 6) {
      throw ArgumentError.value(entry.dice, 'dice', 'must be 1..6');
    }
    if (entry.tokenIndex < 0 || entry.tokenIndex >= tokensPerSeat) {
      throw ArgumentError.value(entry.tokenIndex, 'tokenIndex', 'must be 0..3');
    }
    return entry.seat |
        (entry.dice - 1) << 2 |
        entry.tokenIndex << 5 |
        (entry.unit ? 1 : 0) << 7;
  }

  /// The entry of byte [value], or `null` when it is not a valid one.
  static MoveLogEntry? unpack(int value) {
    if (value < 0 || value > 0xFF) {
      return null;
    }
    final die = (value >> 2) & 7;
    if (die > 5) {
      return null;
    }
    return MoveLogEntry(
      seat: value & 3,
      dice: die + 1,
      tokenIndex: (value >> 5) & 3,
      unit: (value >> 7) & 1 == 1,
    );
  }

  /// The hex string of [log] (lowercase, two digits per entry).
  static String encode(List<MoveLogEntry> log) {
    final out = StringBuffer();
    for (final entry in log) {
      out.write(pack(entry).toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  /// Reads [text]; stops at the first undecodable entry (a non-hex character,
  /// an impossible die or a half entry at the end).
  static LogDecode decode(String text) {
    final entries = <MoveLogEntry>[];
    final pairs = text.length ~/ 2;
    for (var i = 0; i < pairs; i++) {
      final hi = _hex(text.codeUnitAt(2 * i));
      final lo = _hex(text.codeUnitAt(2 * i + 1));
      if (hi < 0 || lo < 0) {
        return LogDecode(entries, badIndex: i, reason: 'not a hex byte');
      }
      final entry = unpack(hi << 4 | lo);
      if (entry == null) {
        return LogDecode(entries, badIndex: i, reason: 'impossible entry');
      }
      entries.add(entry);
    }
    if (text.length.isOdd) {
      return LogDecode(entries, badIndex: pairs, reason: 'cut off');
    }
    return LogDecode(entries);
  }

  static int _hex(int unit) {
    if (unit >= 0x30 && unit <= 0x39) {
      return unit - 0x30;
    }
    if (unit >= 0x61 && unit <= 0x66) {
      return unit - 0x61 + 10;
    }
    if (unit >= 0x41 && unit <= 0x46) {
      return unit - 0x41 + 10;
    }
    return -1;
  }
}
