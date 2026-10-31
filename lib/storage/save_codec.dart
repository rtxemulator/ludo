import 'dart:convert';

import 'package:ludo/engine/ludo_engine.dart';
import 'package:ludo/seats/seats.dart';

import 'game_save.dart';
import 'log_codec.dart';

/// Why a stored save could not be read.
enum SaveProblem {
  /// The text is not JSON.
  notJson,

  /// The JSON is not an object.
  notAnObject,

  /// `schemaVersion` is missing or not a positive integer.
  badSchemaVersion,

  /// The save was written by a newer version of the app.
  newerSchema,

  /// `id` is missing or empty.
  missingId,

  /// `setup` is missing, malformed or has fewer than two players.
  badSetup,

  /// `seed` is missing or not an integer.
  badSeed,

  /// `log` is missing or not a string.
  missingLog,

  /// `log` has an unreadable or cut-off entry ([SaveFailure.salvage] holds
  /// the entries before it).
  corruptLog,

  /// Anything else that went wrong while reading.
  unreadable,
}

/// A save that could not be read, with whatever could still be recovered.
class SaveFailure {
  const SaveFailure(
    this.problem,
    this.message, {
    this.id,
    this.name,
    this.logIndex,
    this.salvage,
  });

  final SaveProblem problem;

  /// Human-readable detail (for logs and the "why is it greyed" line).
  final String message;

  /// The save's id, when it could be read.
  final String? id;

  /// The save's name, when it could be read.
  final String? name;

  /// For [SaveProblem.corruptLog]: the index of the first bad entry.
  final int? logIndex;

  /// For [SaveProblem.corruptLog]: the save with the valid entries before the
  /// damage (no fingerprint), good for a partial replay.
  final GameSave? salvage;

  /// Written by a newer app version rather than damaged.
  bool get incompatible => problem == SaveProblem.newerSchema;

  @override
  String toString() => 'SaveFailure(${problem.name}: $message)';
}

/// Result of reading a save: [SaveDecoded] or [SaveDecodeFailed].
sealed class SaveDecode {
  const SaveDecode();

  /// The save, or `null` when it could not be read.
  GameSave? get save;

  /// The failure, or `null` when the save was read.
  SaveFailure? get failure;
}

final class SaveDecoded extends SaveDecode {
  const SaveDecoded(this.save);

  @override
  final GameSave save;

  @override
  SaveFailure? get failure => null;
}

final class SaveDecodeFailed extends SaveDecode {
  const SaveDecodeFailed(this.failure);

  @override
  final SaveFailure failure;

  @override
  GameSave? get save => null;
}

/// JSON form of a [GameSave] (schema version [saveSchemaVersion]).
///
/// Reading never throws. Unknown fields are ignored and optional ones fall
/// back like `SeatConfig.fromJson`; fields the game cannot be rebuilt
/// without give a typed [SaveFailure]. See `docs/ludo-saves.md` section 4.
abstract final class SaveCodec {
  // ---- Writing ------------------------------------------------------------

  static Map<String, Object?> toJson(GameSave save) => {
        'schemaVersion': save.schemaVersion,
        'id': save.id,
        'name': save.name,
        'createdAt': save.createdAt.millisecondsSinceEpoch,
        'updatedAt': save.updatedAt.millisecondsSinceEpoch,
        'setup': save.setup.toJson(),
        'seed': save.seed.toString(),
        'log': MoveLogCodec.encode(save.log),
        'finished': save.finished,
        'summary': {
          'turn': save.summary.turnNumber,
          'finishOrder': save.summary.finishOrder,
        },
        if (save.check != null) 'check': save.check,
      };

  /// The JSON text of [save].
  static String encode(GameSave save) => jsonEncode(toJson(save));

  // ---- Reading ------------------------------------------------------------

  /// Reads the JSON [text] of a save.
  static SaveDecode decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      return _fail(SaveProblem.notJson, 'not JSON: ${e.message}');
    }
    return fromJson(json);
  }

  /// Reads an already parsed JSON value.
  static SaveDecode fromJson(Object? json) {
    try {
      return _read(json);
    } on Object catch (e) {
      return _fail(SaveProblem.unreadable, 'unexpected: $e');
    }
  }

  static SaveDecode _read(Object? json) {
    final raw = _asMap(json);
    if (raw == null) {
      return _fail(SaveProblem.notAnObject, 'the JSON is not an object');
    }

    final id = raw['id'];
    final rawName = raw['name'];
    final knownId = id is String && id.isNotEmpty ? id : null;
    final knownName = rawName is String ? GameSave.cleanName(rawName) : null;
    SaveDecode fail(SaveProblem problem, String message,
        {int? logIndex, GameSave? salvage}) {
      return _fail(
        problem,
        message,
        id: knownId,
        name: knownName,
        logIndex: logIndex,
        salvage: salvage,
      );
    }

    final version = raw['schemaVersion'];
    if (version is! int || version < 1) {
      return fail(SaveProblem.badSchemaVersion, 'schemaVersion is $version');
    }
    if (version > saveSchemaVersion) {
      return fail(
        SaveProblem.newerSchema,
        'schema $version is newer than $saveSchemaVersion',
      );
    }
    // Older versions would be migrated forward here (none exist yet).

    if (knownId == null) {
      return fail(SaveProblem.missingId, 'id is missing');
    }

    final setup = _setup(raw['setup']);
    if (setup == null) {
      return fail(SaveProblem.badSetup, 'setup is missing or malformed');
    }

    final seed = _seed(raw['seed']);
    if (seed == null) {
      return fail(SaveProblem.badSeed, 'seed is missing or not an integer');
    }

    final logText = raw['log'];
    if (logText is! String) {
      return fail(SaveProblem.missingLog, 'log is missing');
    }

    final updatedMs = _ms(raw['updatedAt']);
    final createdMs = _ms(raw['createdAt']);
    final created = createdMs ?? updatedMs ?? 0;
    final updated = updatedMs ?? createdMs ?? 0;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(created, isUtc: true);

    final decoded = MoveLogCodec.decode(logText);
    final save = GameSave(
      id: knownId,
      name: knownName ?? '',
      createdAt: createdAt,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updated, isUtc: true),
      schemaVersion: saveSchemaVersion,
      setup: setup,
      seed: seed,
      log: decoded.entries,
      finished: raw['finished'] == true,
      summary: _summary(raw['summary']),
      check: _check(raw['check']),
    );
    if (!decoded.clean) {
      return fail(
        SaveProblem.corruptLog,
        'log entry ${decoded.badIndex}: ${decoded.reason}',
        logIndex: decoded.badIndex,
        salvage: save.withLogUnchecked(decoded.entries),
      );
    }
    return SaveDecoded(save);
  }

  static SaveDecodeFailed _fail(
    SaveProblem problem,
    String message, {
    String? id,
    String? name,
    int? logIndex,
    GameSave? salvage,
  }) {
    return SaveDecodeFailed(
      SaveFailure(
        problem,
        message,
        id: id,
        name: name,
        logIndex: logIndex,
        salvage: salvage,
      ),
    );
  }

  // ---- Fields -------------------------------------------------------------

  static Map<String, Object?>? _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    return null;
  }

  /// A setup with a four-entry seat list (each `null` or an object) and at
  /// least two players, else `null`. Fields inside a seat fall back.
  static MatchSetup? _setup(Object? value) {
    final map = _asMap(value);
    if (map == null) {
      return null;
    }
    final seats = map['seats'];
    if (seats is! List || seats.length != seatCount) {
      return null;
    }
    for (final seat in seats) {
      if (seat != null && _asMap(seat) == null) {
        return null;
      }
    }
    final clean = {
      ...map,
      'seats': [for (final seat in seats) _asMap(seat)],
      if (_asMap(map['rules']) != null) 'rules': _asMap(map['rules']),
    };
    final setup = MatchSetup.fromJson(clean);
    return setup.playerCount >= MatchSetup.minPlayers ? setup : null;
  }

  static int? _seed(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static int? _ms(Object? value) => value is int ? value : null;

  static SaveSummary _summary(Object? value) {
    final map = _asMap(value);
    if (map == null) {
      return const SaveSummary();
    }
    final turn = map['turn'];
    final order = map['finishOrder'];
    return SaveSummary(
      turnNumber: turn is int && turn >= 0 ? turn : 0,
      finishOrder: order is List
          ? [
              for (final seat in order)
                if (seat is int && seat >= 0 && seat < seatCount) seat,
            ]
          : const [],
    );
  }

  static final RegExp _checkPattern = RegExp(r'^[0-9a-f]{16}$');

  static String? _check(Object? value) =>
      value is String && _checkPattern.hasMatch(value) ? value : null;
}
