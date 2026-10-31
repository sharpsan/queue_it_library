import 'dart:async';

import 'package:queue_it/queue_it.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('listeners can call the queue', () {
    test('to add an item', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      final events = recordEvents(queue);
      queue.onUpdate.listen((snapshot) {
        if (snapshot.eventItem?.data == 1 &&
            snapshot.eventItem?.status == QueueItemStatus.completed) {
          queue.add(2);
        }
      });
      queue
        ..add(1)
        ..start();
      await queue.running;

      expect(statuses(queue), ['1:completed', '2:completed']);
      // The event the listener caused comes after the one it was handling.
      expect(
        events.indexOf('itemAdded:2:pending'),
        events.indexOf('itemStatusUpdated:1:completed') + 1,
      );
    });

    test('to cancel the other items when one fails', () async {
      final queue = QueueIt<int>(
        parallel: 2,
        itemHandler: (item) async {
          await wait();
          if (item.data == 1) throw Exception('failed');
        },
      );
      addTearDown(queue.dispose);
      queue.onUpdate.listen((snapshot) {
        if (snapshot.eventItem?.status == QueueItemStatus.failed) {
          queue.cancelAll();
        }
      });
      for (var i = 1; i <= 4; i++) {
        queue.add(i);
      }
      queue.start();
      await queue.running;

      expect(statuses(queue),
          ['1:failed', '2:canceled', '3:canceled', '4:canceled']);
    });

    test('to stop and dispose the queue', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      final events = recordEvents(queue);
      var closed = false;
      queue.onUpdate.listen((snapshot) {
        if (snapshot.event == QueueEvent.stoppedProcessing) queue.dispose();
      }, onDone: () => closed = true);
      queue
        ..add(1)
        ..start(stopAutomatically: false);
      await queue.running;

      expect(closed, isTrue);
      expect(events.last, 'stoppedQueue');
    });

    test('without errors reaching the zone', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final queue = QueueIt<int>(itemHandler: (item) {});
        queue.onUpdate.listen((snapshot) {
          if (snapshot.event == QueueEvent.itemAdded &&
              snapshot.eventItem!.data < 3) {
            queue.add(snapshot.eventItem!.data + 1);
          }
        });
        queue
          ..add(1)
          ..start();
        await queue.running;
        expect(queue.items().map((item) => item.data), [1, 2, 3]);
        queue.dispose();
      }, (error, stack) => errors.add(error));

      expect(errors, isEmpty);
    });
  });

  test('sends every listener the events in the same order', () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    final first = recordEvents(queue);
    queue.onUpdate.listen((snapshot) {
      if (snapshot.event == QueueEvent.startedQueue) queue.add(2);
    });
    final last = recordEvents(queue);
    queue
      ..add(1)
      ..start();
    await queue.running;

    expect(last, first);
  });

  test('snapshots hold the queue state at the time of the event', () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    final snapshots = <QueueSnapshot<int>>[];
    queue.onUpdate.listen(snapshots.add);
    queue
      ..add(1)
      ..start();
    await queue.running;

    final processing = snapshots.firstWhere(
        (snapshot) => snapshot.eventItem?.status == QueueItemStatus.processing);
    expect(processing.isStarted, isTrue);
    expect(processing.isProcessing, isTrue);
    expect(processing.retries, 0);
    expect(processing.currentBatchId, queue.currentBatchId);
    // eventItem is a copy; items are the queue's live items.
    expect(processing.eventItem!.status, QueueItemStatus.processing);
    expect(processing.items.single.status, QueueItemStatus.completed);
    expect(snapshots.last.isStarted, isFalse);
  });

  test('snapshots hold copies of the items with deepCopyItemsInSnapshot',
      () async {
    final queue =
        QueueIt<int>(deepCopyItemsInSnapshot: true, itemHandler: (item) {});
    addTearDown(queue.dispose);
    final snapshots = <QueueSnapshot<int>>[];
    queue.onUpdate.listen(snapshots.add);
    queue
      ..add(1)
      ..start();
    await queue.running;

    expect(snapshots.first.items.single.status, QueueItemStatus.pending);
    expect(snapshots.last.items.single.status, QueueItemStatus.completed);
  });

  test('sends no events once disposed', () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    final events = recordEvents(queue);
    final id = queue.add(1);
    queue.dispose();
    final count = events.length;

    queue
      ..removeById(id)
      ..cancelAll();

    expect(events, hasLength(count));
  });
}
