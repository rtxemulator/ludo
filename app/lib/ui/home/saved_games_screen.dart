import 'package:flutter/material.dart';
import 'package:ludo/storage/storage.dart';

import 'save_text.dart';

/// Every saved game, newest first: name, date, who plays, turn and state.
///
/// The list appears at once (decoding only). Each row is then replayed
/// lazily, one at a time between frames, and rows that fail or come from a
/// newer app are greyed out ("Can't open"); deleting them still works.
/// Tapping an unfinished game resumes it; finished games are shown disabled
/// until replay arrives.
class SavedGamesScreen extends StatefulWidget {
  const SavedGamesScreen({
    super.key,
    required this.library,
    required this.onOpen,
  });

  final SaveLibrary library;

  /// Resume [save]; completes when the user comes back.
  final Future<void> Function(GameSave save) onOpen;

  @override
  State<SavedGamesScreen> createState() => _SavedGamesScreenState();
}

class _SavedGamesScreenState extends State<SavedGamesScreen> {
  List<SaveListItem>? _items;
  Object? _error;
  final Map<String, SaveCheck> _checks = {};
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++; // stops a verification still running
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final List<SaveListItem> items;
    try {
      items = await widget.library.list();
    } on Object catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e);
      }
      return;
    }
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _items = items;
      _error = null;
    });
    for (final item in items) {
      if (!item.openable) {
        continue;
      }
      final check = await widget.library.verify(item);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _checks[item.id] = check);
      // Give frames a turn between replays.
      await Future<void>.delayed(Duration.zero);
      if (!mounted || generation != _generation) {
        return;
      }
    }
  }

  /// Whether the row is greyed: unreadable, or failed its replay. A row that
  /// has not been replayed yet is not greyed.
  bool _cannotOpen(SaveListItem item) {
    if (!item.openable) {
      return true;
    }
    final check = _checks[item.id];
    return check != null && !check.ok;
  }

  Future<void> _open(SaveListItem item) async {
    final check = await widget.library.verify(item);
    if (!mounted) {
      return;
    }
    if (!check.resumable) {
      setState(() => _checks[item.id] = check);
      return;
    }
    await widget.onOpen(check.save!);
    if (mounted) {
      await _load();
    }
  }

  Future<void> _rename(SaveListItem item) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: item.name),
    );
    if (name == null || !mounted) {
      return;
    }
    final done = await widget.library.rename(item.id, name);
    if (!mounted) {
      return;
    }
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't rename that game.")),
      );
    }
    await _load();
  }

  Future<void> _delete(SaveListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this game?'),
        content: Text('"${item.name}" will be removed. This cannot be undone.'),
        actions: [
          TextButton(
            key: const ValueKey('delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await widget.library.delete(item.id);
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final Widget body;
    if (_error != null && items == null) {
      body = const Center(child: Text("Couldn't read the saved games."));
    } else if (items == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty) {
      body = const Center(
        key: ValueKey('saved-empty'),
        child: Text('No saved games yet.'),
      );
    } else {
      body = ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) => _row(context, items[index]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Games')),
      body: body,
    );
  }

  Widget _row(BuildContext context, SaveListItem item) {
    final theme = Theme.of(context);
    final broken = _cannotOpen(item);
    final finished = item.finished && !broken;
    final tappable = !broken && !finished;
    final status = broken
        ? "Can't open"
        : finished
            ? 'Finished'
            : 'In progress';
    final who = seatSummary(item.setup);
    final lines = [
      if (!broken) formatSaveDate(item.updatedAt) else '',
      if (who.isNotEmpty) who,
    ].where((l) => l.isNotEmpty).join(' · ');
    final detail = broken ? status : 'Turn ${item.turnNumber} · $status';
    return ListTile(
      key: ValueKey('save-${item.id}'),
      enabled: tappable,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (lines.isNotEmpty) lines, detail].join('\n'),
        style: broken ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      isThreeLine: lines.isNotEmpty,
      onTap: tappable ? () => _open(item) : null,
      trailing: PopupMenuButton<String>(
        key: ValueKey('save-menu-${item.id}'),
        onSelected: (choice) {
          if (choice == 'rename') {
            _rename(item);
          } else {
            _delete(item);
          }
        },
        itemBuilder: (_) => [
          if (!broken)
            const PopupMenuItem(
              value: 'rename',
              child: Text('Rename'),
            ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename game'),
      content: TextField(
        key: const ValueKey('rename-field'),
        controller: _controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('rename-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
