import 'dart:math';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';

import 'fingerprint.dart';
import 'save_codec.dart';

/// The JSON schema version this build writes and reads (`docs/ludo-saves.md`
/// section 4).
const int saveSchemaVersion = 1;

/// Longest save name kept.
const int maxSaveNameLength = 40;

/// What a list row needs without replaying the game.
class SaveSummary {
  const SaveSummary({this.turnNumber = 0, this.finishOrder = const []});

  /// The summary of [state]: its turn number and, once the match is over,
  /// the finishing order.
  factory SaveSummary.of(GameState state) => SaveSummary(
        turnNumber: state.turnNumber,
        finishOrder: state.isOver ? state.finishOrder : const [],
      );

  /// `GameState.turnNumber` after the last decision.
  final int turnNumber;

  /// `GameState.finishOrder` when the game is finished, else empty.
  final List<int> finishOrder;

  @override
  bool operator ==(Object other) =>
      other is SaveSummary &&
      other.turnNumber == turnNumber &&
      _sameInts(other.finishOrder, finishOrder);

  @override
  int get hashCode => Object.hash(turnNumber, Object.hashAll(finishOrder));

  @override
  String toString() => 'SaveSummary(turn $turnNumber, $finishOrder)';
}

/// One saved game: `setup + seed + move log` plus the bookkeeping a list row
/// needs. Immutable; every `with...` returns a copy.
///
/// Everything else (board, bank, rankings) is rebuilt by
/// `SaveReplayer`; see `docs/ludo-saves.md`.
class GameSave {
  GameSave({
    required this.id,
    required String name,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.schemaVersion = saveSchemaVersion,
    required this.setup,
    required this.seed,
    List<MoveLogEntry> log = const [],
    this.finished = false,
    this.summary = const SaveSummary(),
    this.check,
  })  : name = cleanName(name) ?? autoName(createdAt),
        createdAt = _utc(createdAt),
        updatedAt = _utc(updatedAt),
        log = List.unmodifiable(log);

  /// A new save with an empty log. [name] defaults to the auto-name of [now]
  /// (pass local time); [now] is both `createdAt` and `updatedAt`.
  factory GameSave.begin({
    required String id,
    required DateTime now,
    required MatchSetup setup,
    required int seed,
    String? name,
  }) {
    final start = setup.newGame(seed);
    return GameSave(
      id: id,
      name: name ?? '',
      createdAt: now,
      updatedAt: now,
      setup: setup,
      seed: seed,
      summary: SaveSummary.of(start),
      check: StateFingerprint.of(start),
    );
  }

  final String id;

  /// Display name; never blank.
  final String name;

  /// UTC, millisecond precision.
  final DateTime createdAt;

  /// UTC, millisecond precision: the time of the last decision.
  final DateTime updatedAt;

  final int schemaVersion;
  final MatchSetup setup;

  /// The game seed (the first `GameState.rngState`).
  final int seed;

  /// The decisions so far, oldest first.
  final List<MoveLogEntry> log;

  /// Cache of `GameState.isOver`; the replayed state is authoritative.
  final bool finished;
  final SaveSummary summary;

  /// `StateFingerprint` of the state right after the last decision, or
  /// `null` when unchecked.
  final String? check;

  /// Number of decisions made.
  int get moves => log.length;

  /// This save after one more decision.
  ///
  /// [entry] is `Engine.logEntry(before, move)` taken from the state before
  /// the move; [after] must be the state `Engine.apply` returned for it,
  /// *not* a later one (after a roll or an auto-pass): its fingerprint is
  /// what a replay is checked against.
  GameSave withEntry(MoveLogEntry entry, GameState after, DateTime now) {
    return _copy(
      updatedAt: now,
      log: [...log, entry],
      finished: after.isOver,
      summary: SaveSummary.of(after),
      check: StateFingerprint.of(after),
    );
  }

  /// This save renamed (a blank [name] gives the auto-name of `createdAt`).
  /// `updatedAt` is kept.
  GameSave withName(String name) => _copy(name: name);

  GameSave _copy({
    String? name,
    DateTime? updatedAt,
    List<MoveLogEntry>? log,
    bool? finished,
    SaveSummary? summary,
    String? check,
  }) {
    return GameSave(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      schemaVersion: schemaVersion,
      setup: setup,
      seed: seed,
      log: log ?? this.log,
      finished: finished ?? this.finished,
      summary: summary ?? this.summary,
      check: check ?? this.check,
    );
  }

  /// The same save without its fingerprint, with [log] replacing the log
  /// (used for the salvage of a damaged one).
  GameSave withLogUnchecked(List<MoveLogEntry> log) {
    return GameSave(
      id: id,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      schemaVersion: schemaVersion,
      setup: setup,
      seed: seed,
      log: log,
      finished: finished,
      summary: summary,
    );
  }

  Map<String, Object?> toJson() => SaveCodec.toJson(this);

  // ---- Names and ids ------------------------------------------------------

  /// The automatic name of a game started at [time] (pass local time):
  /// `2026-10-26 14:05`.
  static String autoName(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-'
        '${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  /// [raw] trimmed, line breaks turned into spaces and cut to
  /// [maxSaveNameLength] characters; `null` when nothing is left.
  static String? cleanName(String? raw) {
    if (raw == null) {
      return null;
    }
    final text = raw.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (text.isEmpty) {
      return null;
    }
    final runes = text.runes;
    if (runes.length <= maxSaveNameLength) {
      return text;
    }
    return String.fromCharCodes(runes.take(maxSaveNameLength)).trim();
  }

  /// A fresh opaque id: the time in base 36 plus 32 random bits.
  static String newId(DateTime now, [Random? random]) {
    final rng = random ?? Random();
    final time = now.toUtc().millisecondsSinceEpoch.toRadixString(36);
    final salt = rng.nextInt(1 << 32).toRadixString(36);
    return '$time-$salt';
  }

  static DateTime _utc(DateTime time) =>
      DateTime.fromMillisecondsSinceEpoch(time.millisecondsSinceEpoch,
          isUtc: true);

  @override
  bool operator ==(Object other) =>
      other is GameSave &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.schemaVersion == schemaVersion &&
      other.setup == setup &&
      other.seed == seed &&
      other.finished == finished &&
      other.summary == summary &&
      other.check == check &&
      _sameLog(other.log, log);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        updatedAt,
        schemaVersion,
        setup,
        seed,
        finished,
        summary,
        check,
        Object.hashAll(log),
      );

  @override
  String toString() => 'GameSave($id "$name", ${log.length} moves'
      '${finished ? ', finished' : ''})';
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _sameLog(List<MoveLogEntry> a, List<MoveLogEntry> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
