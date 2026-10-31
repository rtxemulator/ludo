import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/storage/storage.dart';

import 'package:ludo_app/storage/save_flush_observer.dart';

class _CountingQueue extends SaveWriteQueue {
  _CountingQueue() : super(InMemorySaveStore());

  int flushes = 0;

  @override
  Future<void> flush() {
    flushes++;
    return super.flush();
  }
}

void main() {
  testWidgets('the queue is flushed whenever the app leaves the foreground',
      (tester) async {
    final queue = _CountingQueue();
    await tester.pumpWidget(
      SaveFlushObserver(queue: queue, child: const SizedBox()),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(queue.flushes, 0);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      final before = queue.flushes;
      tester.binding.handleAppLifecycleStateChanged(state);
      expect(queue.flushes, before + 1, reason: '$state');
    }
  });

  testWidgets('it stops listening when removed', (tester) async {
    final queue = _CountingQueue();
    await tester.pumpWidget(
      SaveFlushObserver(queue: queue, child: const SizedBox()),
    );
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(queue.flushes, 0);
  });
}
