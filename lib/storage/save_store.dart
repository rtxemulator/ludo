import 'package:ludo/seats/seats.dart';

import 'game_save.dart';
import 'save_codec.dart';

/// Whether a stored save can be opened.
enum SaveStatus {
  /// Readable; still to be confirmed by a replay when opened.
  ok,

  /// Unreadable or damaged: listed greyed, deletable.
  damaged,

  /// Written by a newer app version: listed greyed, deletable.
  incompatible,
}

/// A row of the saved-games list, built without replaying the game.
class SaveListItem {
  const SaveListItem({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.finished = false,
    this.turnNumber = 0,
    this.moves = 0,
    this.finishOrder = const [],
    this.setup,
    this.problem,
    this.salvagedMoves,
  });

  /// The row of a readable [save].
  factory SaveListItem.fromSave(GameSave save) => SaveListItem(
        id: save.id,
        name: save.name,
        createdAt: save.createdAt,
        updatedAt: save.updatedAt,
        status: SaveStatus.ok,
        finished: save.finished,
        turnNumber: save.summary.turnNumber,
        moves: save.moves,
        finishOrder: save.summary.finishOrder,
        setup: save.setup,
      );

  /// The greyed row of a save that could not be read. [id], [name] and
  /// [updatedAt] are what the store knows about the row on its own.
  factory SaveListItem.fromFailure(
    SaveFailure failure, {
    required String id,
    String? name,
    DateTime? updatedAt,
  }) {
    final when =
        updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return SaveListItem(
      id: id,
      name: failure.name ?? name ?? id,
      createdAt: failure.salvage?.createdAt ?? when,
      updatedAt: when,
      status:
          failure.incompatible ? SaveStatus.incompatible : SaveStatus.damaged,
      problem: failure.message,
      salvagedMoves: failure.salvage?.moves,
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SaveStatus status;
  final bool finished;
  final int turnNumber;
  final int moves;
  final List<int> finishOrder;

  /// The setup, for the row's subtitle; `null` when unreadable.
  final MatchSetup? setup;

  /// Why the row is greyed.
  final String? problem;

  /// For a damaged log: how many decisions are still readable (a partial
  /// replay is possible).
  final int? salvagedMoves;

  /// Whether the row may be opened (replay still decides in the end).
  bool get openable => status == SaveStatus.ok;
}

/// Where saves live. Implemented in memory here and by sqflite in the app.
///
/// Implementations store the JSON of `SaveCodec.encode`, never throw on a
/// damaged row, and never alter or delete a row on their own.
abstract interface class SaveStore {
  /// Every save, newest `updatedAt` first (ties by id), damaged ones
  /// included as greyed rows. Decodes only; does not replay.
  Future<List<SaveListItem>> list();

  /// The decoded save, a failure for a damaged row, or `null` for an unknown
  /// id.
  Future<SaveDecode?> get(String id);

  /// Inserts or replaces the save with `save.id`.
  Future<void> put(GameSave save);

  /// Renames a readable save, keeping its `updatedAt`. `false` when the id is
  /// unknown, the row is damaged or [name] is blank.
  Future<bool> rename(String id, String name);

  /// Deletes the save (damaged or not). `false` when the id is unknown.
  Future<bool> delete(String id);
}
