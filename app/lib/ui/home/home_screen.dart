import 'package:flutter/material.dart';
import 'package:ludo/storage/storage.dart';

/// The start screen: Play, Continue last game (when there is one) and Saved
/// Games. Settings stay in the in-game menu.
///
/// The screen only asks what to open; the caller navigates. Each callback's
/// future completes when the user comes back, and the screen then refreshes
/// (a game played meanwhile changes what "Continue" points at).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.library,
    required this.onPlay,
    required this.onContinue,
    required this.onSavedGames,
  });

  final SaveLibrary library;

  /// "Play": open the new-game setup.
  final Future<void> Function() onPlay;

  /// "Continue last game": resume [save].
  final Future<void> Function(GameSave save) onContinue;

  /// "Saved Games": open the list.
  final Future<void> Function() onSavedGames;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GameSave? _last;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    GameSave? last;
    try {
      final items = await widget.library.list();
      last = await widget.library.lastResumable(items);
    } on Object {
      last = null;
    }
    if (mounted) {
      setState(() => _last = last);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _last;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ludo',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium,
                  ),
                  const SizedBox(height: 40),
                  FilledButton(
                    key: const ValueKey('home-play'),
                    onPressed: () => _run(widget.onPlay),
                    child: const Text('Play'),
                  ),
                  if (last != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      key: const ValueKey('home-continue'),
                      onPressed: () => _run(() => widget.onContinue(last)),
                      child: const Text('Continue last game'),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        last.name,
                        key: const ValueKey('home-continue-name'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey('home-saved'),
                    onPressed: () => _run(widget.onSavedGames),
                    child: const Text('Saved Games'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
