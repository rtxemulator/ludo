import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:ludo/storage/storage.dart';

/// Flushes the save write queue whenever the app leaves the foreground
/// (inactive, hidden, paused, detached), so the last move is on disk before
/// the system may stop the process. Never blocks: the flush runs in the
/// background.
class SaveFlushObserver extends StatefulWidget {
  const SaveFlushObserver(
      {super.key, required this.queue, required this.child});

  final SaveWriteQueue queue;
  final Widget child;

  @override
  State<SaveFlushObserver> createState() => _SaveFlushObserverState();
}

class _SaveFlushObserverState extends State<SaveFlushObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.queue.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
