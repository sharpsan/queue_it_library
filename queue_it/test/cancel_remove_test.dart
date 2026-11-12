import 'dart:async';

import 'package:queue_it/queue_it.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Allocates enough to make the VM collect garbage, old objects included.
Future<void> _collectGarbage() async {
  for (var round = 0; round < 2; round++) {
    await wait(10);
    for (var i = 0; i < 20; i++) {
      var garbage = <List<int>>[];
      for (var j = 0; j < 2000; j++) {
        garbage.add(List<int>.filled(1000, j));
      }
      garbage = [];
    }
  }
}

void main() {
  late Gate<int> gate;
  late QueueIt<int> queue;

  setUp(() {
    gate = Gate<int>();
    queue = QueueIt<int>(retries: 2, itemHandler: gate.call);
    addTearDown(queue.dispose);
  });

  QueueItem<int> item(int data) =>
      queue.items().firstWhere((item) => item.data == data);

  /// A queue whose item fails, then waits for [delay] to be retried.
  QueueIt<int> failing({Duration delay = const Duration(hours: 1)}) {
    final queue = QueueIt<int>(
      retries: 1,
      retryDelay: (retry) => delay,
      itemHandler: (item) => throw Exception('failed'),
    );
    addTearDown(queue.dispose);
    return queue;
  }

  group('cancel', () {
    test('skips a pending item', () async {
      queue
        ..add(1)
        ..add(2)
        ..start();
      await wait();

      expect(queue.cancel(item(2)), isTrue);
      gate.release(1);
      await queue.running;

      expect(gate.started, [1]);
      expect(statuses(queue), ['1:completed', '2:canceled']);
    });

    test('keeps a processing item canceled when its handler returns', () async {
      queue
        ..add(1)
        ..start();
      await wait();

      expect(queue.cancel(item(1)), isTrue);
      expect(item(1).status, QueueItemStatus.canceled);
      gate.release(1);
      await queue.running;

      expect(statuses(queue), ['1:canceled']);
    });

    test('does not retry a processing item when its handler throws', () async {
      queue
        ..add(1)
        ..start();
      await wait();

      queue.cancel(item(1));
      gate.release(1, Exception('failed'));
      await queue.running;

      expect(gate.started, [1]);
      expect(statuses(queue), ['1:canceled']);
    });

    test('refuses finished items and unknown ids', () async {
      final finished = QueueIt<int>(itemHandler: (item) {
        if (item.data == 2) throw Exception('failed');
      });
      addTearDown(finished.dispose);
      finished
        ..add(1)
        ..add(2)
        ..start();
      await finished.running;

      for (final item in finished.items()) {
        expect(finished.cancel(item), isFalse);
      }
      expect(finished.cancelById('unknown'), isFalse);
      expect(statuses(finished), ['1:completed', '2:failed']);
    });

    test('works with a copy of the item', () async {
      QueueItem<int>? copy;
      queue.onUpdate.listen((snapshot) => copy ??= snapshot.eventItem);
      queue.add(1);

      expect(queue.cancel(copy!), isTrue);

      expect(statuses(queue), ['1:canceled']);
    });

    test('sends the canceled status', () async {
      final events = recordEvents(queue);
      final id = queue.add(1);

      queue.cancelById(id);

      expect(events.last, 'itemStatusUpdated:1:canceled');
    });
  });

  group('cancelAll', () {
    test('cancels pending and processing items only', () async {
      final events = recordEvents(queue);
      queue
        ..add(1)
        ..add(2)
        ..add(3)
        ..start();
      await wait();
      gate.release(1);
      await wait();

      queue.cancelAll();
      gate.release(2);
      await queue.running;

      expect(gate.started, [1, 2]);
      expect(statuses(queue), ['1:completed', '2:canceled', '3:canceled']);
      expect(events, contains('canceledAll'));
    });

    test('lets the queue stop by itself when it cancels the waiting retries',
        () async {
      final queue = failing();
      final events = recordEvents(queue);
      queue
        ..add(1)
        ..start();
      await wait(5);
      expect(statuses(queue), ['1:pending']);
      events.clear();

      queue.cancelAll();

      await queue.running.timeout(const Duration(seconds: 1));
      expect(queue.isProcessing, isFalse);
      expect(events, ['canceledAll', 'stoppedProcessing', 'stoppedQueue']);
    });
  });

  group('remove', () {
    test('skips a pending item', () async {
      final events = recordEvents(queue);
      queue
        ..add(1)
        ..add(2)
        ..start();
      await wait();

      final removed = item(2);
      expect(queue.remove(removed), isTrue);
      gate.release(1);
      await queue.running;

      expect(gate.started, [1]);
      expect(statuses(queue), ['1:completed']);
      expect(removed.status, QueueItemStatus.removed);
      expect(removed.removedAt, isNotNull);
      expect(events, contains('itemRemoved:2:removed'));
    });

    test('ignores the outcome of a processing item', () async {
      final events = recordEvents(queue);
      queue
        ..add(1)
        ..start();
      await wait();

      final removed = item(1);
      queue.remove(removed);
      gate.release(1, Exception('failed'));
      await queue.running;

      expect(gate.started, [1]);
      expect(removed.status, QueueItemStatus.removed);
      expect(events.where((event) => event.endsWith(':failed')), isEmpty);
    });

    test('works with a copy of the item and by id', () {
      final id = queue.add(1);
      queue.add(2);

      expect(queue.remove(queue.items().first.copyWith()), isTrue);
      expect(queue.removeById(id), isFalse);
      expect(queue.removeById(queue.items().single.id), isTrue);
      expect(queue.items(), isEmpty);
    });

    test('leaves the rest of the current batch when it removes the first item',
        () {
      final snapshots = <QueueSnapshot<int>>[];
      queue.onUpdate.listen(snapshots.add);
      final first = queue.add(1);
      queue
        ..add(2)
        ..add(3);

      queue.removeById(first);

      expect(queue.currentBatchItems.map((item) => item.data), [2, 3]);
      expect(snapshots.last.items.map((item) => item.data), [2, 3]);
    });

    test('lets the queue stop by itself when it removes the waiting retry',
        () async {
      final queue = failing();
      final events = recordEvents(queue);
      final id = queue.add(1);
      queue.start();
      await wait(5);
      expect(statuses(queue), ['1:pending']);
      events.clear();

      queue.removeById(id);

      await queue.running.timeout(const Duration(seconds: 1));
      expect(queue.isProcessing, isFalse);
      expect(events,
          ['itemRemoved:1:removed', 'stoppedProcessing', 'stoppedQueue']);
    });

    test('lets go of the item right away', () async {
      // A stopped queue with an item waiting in front of the removed ones.
      final queue = QueueIt<List<int>>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      queue.add([0]);
      WeakReference<List<int>> addAndRemove() {
        final data = List<int>.filled(100000, 1);
        queue.removeById(queue.add(data));
        return WeakReference(data);
      }

      final removed = [for (var i = 0; i < 10; i++) addAndRemove()];
      // Nothing holds these, so they show whether garbage collection ran.
      final unused = [
        for (var i = 0; i < 10; i++) WeakReference(List<int>.filled(100000, 1)),
      ];
      await _collectGarbage();

      if (unused.any((reference) => reference.target != null)) {
        markTestSkipped("Garbage collection didn't run.");
        return;
      }
      expect(removed.where((reference) => reference.target != null), isEmpty);
    });

    test('takes about as long as adding, however many items there are', () {
      // Removing items as they finish keeps a long-lived queue small.
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      const count = 50000;
      final adding = Stopwatch()..start();
      final ids = [for (var i = 0; i < count; i++) queue.add(i)];
      adding.stop();

      final removing = Stopwatch()..start();
      ids.forEach(queue.removeById);
      removing.stop();

      expect(queue.items(), isEmpty);
      // Before, each removal went through the list: about 100 times longer.
      expect(removing.elapsedMicroseconds,
          lessThan(adding.elapsedMicroseconds * 10 + 100000));
    });
  });

  group('removeAll', () {
    test('stops removed items from being processed', () async {
      final events = recordEvents(queue);
      queue
        ..add(1)
        ..add(2)
        ..add(3)
        ..start(stopAutomatically: false);
      await wait();

      final removed = queue.items().toList();
      queue.removeAll();
      gate.release(1);
      await wait();

      expect(gate.started, [1]);
      expect(queue.items(), isEmpty);
      expect(removed.map((item) => item.status),
          everyElement(QueueItemStatus.removed));
      expect(events, contains('removedAll'));
      queue.stop();
      await queue.running;
    });

    test('leaves the current batch empty', () {
      final snapshots = <QueueSnapshot<int>>[];
      queue.onUpdate.listen(snapshots.add);
      queue
        ..add(1)
        ..add(2);

      queue.removeAll();

      expect(queue.currentBatchItems, isEmpty);
      expect(snapshots.last.event, QueueEvent.removedAll);
      expect(snapshots.last.items, isEmpty);
    });

    test('forgets the ids, which can be used again', () async {
      queue.add(1, id: 'a');

      queue.removeAll();

      expect(queue.hasItemById('a'), isFalse);
      expect(queue.removeById('a'), isFalse);
      expect(queue.cancelById('a'), isFalse);
      await expectLater(queue.waitFor('a'), throwsArgumentError);
      expect(queue.add(2, id: 'a'), 'a');
      expect(statuses(queue), ['2:pending']);
    });

    test(
        'starts a new batch for an item added after a listener removes '
        'everything as an attempt fails', () async {
      final queue = QueueIt<int>(
        retries: 1,
        itemHandler: (item) => throw Exception('failed'),
      );
      addTearDown(queue.dispose);
      String? added;
      queue.onUpdate.listen((snapshot) {
        if (snapshot.eventItem?.status == QueueItemStatus.failed &&
            added == null) {
          queue.removeAll();
          added = queue.add(2);
        }
      });
      queue.add(1);
      final firstBatch = queue.currentBatchId;
      queue.start(stopAutomatically: false);
      await wait(10);

      expect(added, isNotNull);
      expect(queue.items().single.batchId, isNot(firstBatch));
    });
  });

  for (final (name, stop) in [
    ('cancel', (QueueItem<int> item) => queue.cancel(item)),
    ('remove', (QueueItem<int> item) => queue.remove(item)),
    ('cancelAll', (QueueItem<int> item) => queue.cancelAll()),
    ('removeAll', (QueueItem<int> item) => queue.removeAll()),
  ]) {
    test(
        '$name leaves a processing item its place among the parallel items '
        'until its handler returns', () async {
      queue
        ..add(1)
        ..start(stopAutomatically: false);
      await wait();

      stop(item(1));
      queue.add(2);
      await wait(20);
      expect(gate.started, [1]);

      gate.release(1);
      await wait();
      expect(gate.started, [1, 2]);
    });
  }

  // If the timer of a retry that was canceled or removed fired, the finished
  // item would be queued again: a stopped queue would count it as work, and
  // the next start would begin and end processing with nothing to do.
  for (final (name, finish) in <(String, void Function(QueueIt<int>, String))>[
    ('cancelById', (queue, id) => queue.cancelById(id)),
    ('cancelAll', (queue, id) => queue.cancelAll()),
    ('removeById', (queue, id) => queue.removeById(id)),
    ('removeAll', (queue, id) => queue.removeAll()),
  ]) {
    test('$name stops the timer of a waiting retry', () async {
      final timers = <Timer>[];
      await runZoned(
        () async {
          final queue = failing(delay: const Duration(milliseconds: 20));
          final id = queue.add(1);
          queue.start();
          await wait(5);

          finish(queue, id);
          await queue.running;

          expect(timers.where((timer) => timer.isActive), isEmpty);
          final events = recordEvents(queue);
          final firstBatch = queue.currentBatchId;
          await wait(60);
          // The next item starts a batch: nothing is left of the last one.
          queue.add(2);
          expect(queue.currentBatchId, isNot(firstBatch));
          expect(events, ['itemAdded:2:pending']);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            if (duration == const Duration(milliseconds: 20)) {
              timers.add(timer);
            }
            return timer;
          },
        ),
      );
    });
  }

  test('cancels and removes items after dispose failed their waitFor',
      () async {
    final id = queue.add(1);
    final finished = queue.waitFor(id);
    queue.dispose();
    await expectLater(finished, throwsStateError);

    expect(queue.cancelById(id), isTrue);
    expect(queue.removeById(id), isTrue);
  });
}
