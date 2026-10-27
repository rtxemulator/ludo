import 'game_save.dart';
import 'save_codec.dart';
import 'save_store.dart';

/// A [SaveStore] that keeps the encoded JSON in a map, like a database
/// would, so tests exercise the codec too.
class InMemorySaveStore implements SaveStore {
  final Map<String, _Row> _rows = {};

  /// Number of rows, damaged ones included.
  int get length => _rows.length;

  @override
  Future<List<SaveListItem>> list() async {
    final items = <SaveListItem>[
      for (final entry in _rows.entries) _item(entry.key, entry.value),
    ];
    items.sort((a, b) {
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return items;
  }

  @override
  Future<SaveDecode?> get(String id) async {
    final row = _rows[id];
    return row == null ? null : SaveCodec.decode(row.json);
  }

  @override
  Future<void> put(GameSave save) async {
    _rows[save.id] = _Row(save.name, save.updatedAt, SaveCodec.encode(save));
  }

  @override
  Future<bool> rename(String id, String name) async {
    final row = _rows[id];
    final cleaned = GameSave.cleanName(name);
    if (row == null || cleaned == null) {
      return false;
    }
    final save = SaveCodec.decode(row.json).save;
    if (save == null) {
      return false;
    }
    await put(save.withName(cleaned));
    return true;
  }

  @override
  Future<bool> delete(String id) async => _rows.remove(id) != null;

  /// Plants a row with arbitrary [json] (a damaged or newer-version save) for
  /// tests and importers. [name] and [updatedAt] play the role of the
  /// database columns a real store keeps next to the JSON.
  void putRaw(String id, String json, {String? name, DateTime? updatedAt}) {
    _rows[id] = _Row(
      name ?? id,
      updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      json,
    );
  }

  SaveListItem _item(String id, _Row row) {
    final decoded = SaveCodec.decode(row.json);
    final save = decoded.save;
    if (save != null) {
      return SaveListItem.fromSave(save);
    }
    return SaveListItem.fromFailure(
      decoded.failure!,
      id: id,
      name: row.name,
      updatedAt: row.updatedAt,
    );
  }
}

class _Row {
  const _Row(this.name, this.updatedAt, this.json);

  final String name;
  final DateTime updatedAt;
  final String json;
}
