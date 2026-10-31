import 'package:ludo/storage/storage.dart';
import 'package:sqflite/sqflite.dart';

/// [SaveStore] on SQLite (sqflite). One row per save.
///
/// The database opens on first use, so building the store costs nothing at
/// launch. `json` holds `SaveCodec.encode`; the other columns only serve
/// listing and ordering, and `list()` never replays a game.
///
/// The SQL cannot be unit tested without a device; see the device checklist.
class SqfliteSaveStore implements SaveStore {
  /// Opens `ludo.db` in the app's databases folder on first use.
  SqfliteSaveStore({String? path}) : _path = path;

  /// Wraps an already open [database] (the table must exist).
  SqfliteSaveStore.withDatabase(Database database)
      : _path = null,
        _db = Future<Database>.value(database);

  static const String table = 'saves';
  static const int databaseVersion = 1;

  final String? _path;
  Future<Database>? _db;

  Future<Database> get _database => _db ??= _open();

  Future<Database> _open() async {
    final path = _path ?? '${await getDatabasesPath()}/ludo.db';
    return openDatabase(
      path,
      version: databaseVersion,
      onCreate: (db, version) => db.execute('''
CREATE TABLE $table (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  finished INTEGER NOT NULL,
  schema_version INTEGER NOT NULL,
  json TEXT NOT NULL
)'''),
    );
  }

  /// Closes the database (the next call reopens it).
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) {
      await (await db).close();
    }
  }

  @override
  Future<List<SaveListItem>> list() async {
    final db = await _database;
    final rows = await db.query(
      table,
      columns: ['id', 'name', 'updated_at', 'json'],
      orderBy: 'updated_at DESC, id ASC',
    );
    final items = <SaveListItem>[];
    for (final row in rows) {
      final id = '${row['id']}';
      final decoded = SaveCodec.decode(_jsonOf(row));
      final save = decoded.save;
      if (save != null) {
        items.add(SaveListItem.fromSave(save));
      } else {
        items.add(SaveListItem.fromFailure(
          decoded.failure!,
          id: id,
          name: row['name'] as String?,
          updatedAt: _time(row['updated_at']),
        ));
      }
    }
    return items;
  }

  @override
  Future<SaveDecode?> get(String id) async {
    final db = await _database;
    final rows = await db.query(
      table,
      columns: ['json'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return SaveCodec.decode(_jsonOf(rows.first));
  }

  @override
  Future<void> put(GameSave save) async {
    final db = await _database;
    await db.insert(
      table,
      _values(save),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> rename(String id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      return false;
    }
    final db = await _database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        table,
        columns: ['json'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return false;
      }
      final save = SaveCodec.decode(_jsonOf(rows.first)).save;
      if (save == null) {
        return false;
      }
      await txn.insert(
        table,
        _values(save.withName(clean)),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    });
  }

  @override
  Future<bool> delete(String id) async {
    final db = await _database;
    final count = await db.delete(table, where: 'id = ?', whereArgs: [id]);
    return count > 0;
  }

  static Map<String, Object?> _values(GameSave save) => {
        'id': save.id,
        'name': save.name,
        'created_at': save.createdAt.millisecondsSinceEpoch,
        'updated_at': save.updatedAt.millisecondsSinceEpoch,
        'finished': save.finished ? 1 : 0,
        'schema_version': save.schemaVersion,
        'json': SaveCodec.encode(save),
      };

  static String _jsonOf(Map<String, Object?> row) {
    final text = row['json'];
    return text is String ? text : '';
  }

  static DateTime? _time(Object? ms) =>
      ms is int ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true) : null;
}
