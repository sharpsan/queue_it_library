import 'package:queue_it/queue_it.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('ids', () {
    test('are UUIDs, or the id passed to add', () {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);

      final uuid = queue.add(1);
      final custom = queue.add(2, id: 'two');

      expect(uuid, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(custom, 'two');
      expect(queue.hasItemById('two'), isTrue);
      expect(queue.hasItem(queue.items().first.copyWith()), isTrue);
      expect(queue.hasItemById('three'), isFalse);
      expect(
        QueueItem(data: 3, status: QueueItemStatus.pending, batchId: 'b').id,
        matches(RegExp(r'^[0-9a-f-]{36}$')),
      );
    });

    test('must be unique', () {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      queue.add(1, id: 'a');

      expect(() => queue.add(2, id: 'a'), throwsArgumentError);
      expect(queue.items(), hasLength(1));
    });

    test('are unique phrases with useFriendlyIds', () {
      final queue = QueueIt<int>(useFriendlyIds: true, itemHandler: (item) {});
      addTearDown(queue.dispose);

      final ids = [for (var i = 0; i < 100; i++) queue.add(i)];

      expect(ids.toSet(), hasLength(100));
      expect(ids.first, matches(RegExp(r'^\w+ \w+ \w+$')));
    });
  });

  group('batches', () {
    test('group the items added until every item has finished', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      final snapshots = <QueueSnapshot<int>>[];
      queue.onUpdate.listen(snapshots.add);
      queue
        ..add(1)
        ..add(2);
      final first = queue.currentBatchId;
      queue.start();
      await queue.running;
      expect(queue.currentBatchId, first);

      queue.add(3);

      expect(queue.currentBatchId, isNot(first));
      expect(queue.items().map((item) => item.batchId),
          [first, first, queue.currentBatchId]);
      expect(queue.currentBatchItems.map((item) => item.data), [3]);
      expect(queue.items(first).map((item) => item.data), [1, 2]);
      expect(snapshots.last.items.map((item) => item.data), [3]);
    });

    test('carry on while items are pending in a stopped queue', () {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      queue.add(1);
      final first = queue.currentBatchId;

      queue.add(2);

      expect(queue.currentBatchId, first);
    });

    test('keep an item that is about to be retried', () async {
      final queue = QueueIt<int>(
        retries: 1,
        itemHandler: (item) {
          if (item.data == 1 && item.retryCount == 0) {
            throw Exception('flaky');
          }
        },
      );
      addTearDown(queue.dispose);
      queue.onUpdate.listen((snapshot) {
        final item = snapshot.eventItem;
        if (item?.data != 1) return;
        // While the first attempt's failed and pending events are sent.
        if (item!.status == QueueItemStatus.failed) queue.add(2);
        if (item.status == QueueItemStatus.pending && item.retryCount == 1) {
          queue.add(3);
        }
      });
      queue
        ..add(1)
        ..start();
      await queue.running;

      expect(statuses(queue), ['1:completed', '2:completed', '3:completed']);
      expect(queue.items().map((item) => item.batchId).toSet(),
          {queue.currentBatchId});
    });

    test('keep an item that its handler sends back to pending', () async {
      final queue = QueueIt<int>(itemHandler: (item) {
        if (item.data == 1 && item.retryCount == 0) {
          item.nextStatus = QueueItemStatus.pending;
        }
      });
      addTearDown(queue.dispose);
      queue.onUpdate.listen((snapshot) {
        final item = snapshot.eventItem;
        if (item?.data == 1 && item?.status == QueueItemStatus.pending) {
          if (item!.retryCount == 1) queue.add(2);
        }
      });
      queue
        ..add(1)
        ..start();
      await queue.running;

      expect(statuses(queue), ['1:completed', '2:completed']);
      expect(queue.currentBatchItems.map((item) => item.data), [1, 2]);
    });

    test("don't wait for the handler of a canceled item", () async {
      final gate = Gate<int>();
      final queue = QueueIt<int>(itemHandler: gate.call);
      addTearDown(queue.dispose);
      final id = queue.add(1);
      final first = queue.currentBatchId;
      queue.start();
      await wait();
      queue.cancelById(id);

      queue.add(2);

      expect(queue.currentBatchId, isNot(first));
      gate.release(1);
    });
  });

  group('nextStatus', () {
    Future<QueueIt<int>> run(
      QueueItemStatus? Function(QueueItem<int> item) nextStatus, {
      int retries = 0,
    }) async {
      final queue = QueueIt<int>(
        retries: retries,
        itemHandler: (item) => item.nextStatus = nextStatus(item),
      );
      addTearDown(queue.dispose);
      queue
        ..add(1)
        ..start();
      await queue.running;
      return queue;
    }

    test('cancels the item, with one event', () async {
      final queue = QueueIt<int>(
        itemHandler: (item) => item.nextStatus = QueueItemStatus.canceled,
      );
      addTearDown(queue.dispose);
      final events = recordEvents(queue);
      queue
        ..add(1)
        ..start();
      await queue.running;

      expect(statuses(queue), ['1:canceled']);
      expect(
          events.where((event) => event.endsWith(':canceled')), hasLength(1));
    });

    test('removes the item', () async {
      final queue = await run((item) => QueueItemStatus.removed);

      expect(queue.items(), isEmpty);
    });

    test('fails the item without an error, with retries', () async {
      final queue = await run((item) => QueueItemStatus.failed, retries: 2);

      final item = queue.items().single;
      expect(item.status, QueueItemStatus.failed);
      expect(item.retryCount, 2);
      expect(item.error, isNull);
    });

    test('processes the item again after the waiting items', () async {
      final processed = <String>[];
      final queue = QueueIt<int>(itemHandler: (item) {
        processed.add('${item.data}.${item.retryCount}');
        if (item.data == 1 && item.retryCount < 2) {
          item.nextStatus = QueueItemStatus.pending;
        }
      });
      addTearDown(queue.dispose);
      queue
        ..add(1)
        ..add(2)
        ..start();
      await queue.running;

      expect(processed, ['1.0', '2.0', '1.1', '1.2']);
      expect(statuses(queue), ['1:completed', '2:completed']);
    });

    test('fails the item when set to processing', () async {
      final queue = await run((item) => QueueItemStatus.processing);

      final item = queue.items().single;
      expect(item.status, QueueItemStatus.failed);
      expect(item.error, isStateError);
    });

    test('is cleared after each attempt', () async {
      final queue = await run(
        (item) => item.retryCount == 0 ? QueueItemStatus.failed : null,
        retries: 1,
      );

      final item = queue.items().single;
      expect(item.status, QueueItemStatus.completed);
      expect(item.nextStatus, isNull);
    });
  });

  group('waitFor', () {
    test('completes with a copy of the finished item', () async {
      final gate = Gate<int>();
      final queue = QueueIt<int>(itemHandler: gate.call);
      addTearDown(queue.dispose);
      final id = queue.add(1);
      queue.start();
      final finished = queue.waitFor(id);
      await wait();

      gate.release(1);
      final item = await finished;

      expect(item.status, QueueItemStatus.completed);
      expect(item, isNot(same(queue.items().single)));
    });

    test('waits for the retries', () async {
      final queue = QueueIt<int>(
        retries: 2,
        itemHandler: (item) => throw Exception('failed'),
      );
      addTearDown(queue.dispose);
      final id = queue.add(1);
      queue.start();

      final item = await queue.waitFor(id);

      expect(item.status, QueueItemStatus.failed);
      expect(item.retryCount, 2);
    });

    test('completes when the item is canceled or removed', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      final first = queue.add(1);
      final second = queue.add(2);
      final canceled = queue.waitFor(first);
      final removed = queue.waitFor(second);

      queue
        ..cancelById(first)
        ..removeById(second);

      expect((await canceled).status, QueueItemStatus.canceled);
      expect((await removed).status, QueueItemStatus.removed);
    });

    test('completes right away for a finished item', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      final id = queue.add(1);
      queue.start();
      await queue.running;

      expect((await queue.waitFor(id)).status, QueueItemStatus.completed);
    });

    test('fails for an unknown id', () {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);

      expect(queue.waitFor('unknown'), throwsArgumentError);
    });

    test('fails when the queue is disposed first', () {
      final queue = QueueIt<int>(itemHandler: (item) {});
      final finished = queue.waitFor(queue.add(1));

      queue.dispose();

      expect(finished, throwsStateError);
    });

    test('fails when called after the queue is disposed', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      final id = queue.add(1);

      queue.dispose();

      await expectLater(
        queue.waitFor(id).timeout(const Duration(seconds: 1)),
        throwsStateError,
      );
    });

    test("fails when called by a listener of the disposed queue's last events",
        () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      final id = queue.add(1);
      final waited = <Future<QueueItem<int>>>[];
      queue.onUpdate.listen((snapshot) {
        if (snapshot.event == QueueEvent.startedQueue) queue.dispose();
        // Sent after startedQueue has reached the listeners, so after dispose.
        if (snapshot.event == QueueEvent.stoppedQueue) {
          waited.add(queue.waitFor(id));
        }
      });

      queue.start();

      await expectLater(
        waited.single.timeout(const Duration(seconds: 1)),
        throwsStateError,
      );
    });

    test('gives the item as it finished, whatever the listeners do then',
        () async {
      final queue = QueueIt<int>(itemHandler: (item) {
        if (item.data == 2) throw Exception('failed');
      });
      addTearDown(queue.dispose);
      // Removes the items as they finish.
      queue.onUpdate.listen((snapshot) {
        final item = snapshot.eventItem;
        if (item?.status == QueueItemStatus.completed ||
            item?.status == QueueItemStatus.failed) {
          queue.remove(item!);
        }
      });
      final completed = queue.waitFor(queue.add(1));
      final failed = queue.waitFor(queue.add(2));

      queue.start();

      expect((await completed).status, QueueItemStatus.completed);
      expect((await failed).status, QueueItemStatus.failed);
      expect(queue.items(), isEmpty);
    });

    test('gives the item as it finished when a listener then disposes',
        () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      queue.onUpdate.listen((snapshot) {
        if (snapshot.eventItem?.status == QueueItemStatus.completed) {
          queue.dispose();
        }
      });
      final finished = queue.waitFor(queue.add(1));

      queue.start();

      expect((await finished).status, QueueItemStatus.completed);
    });

    test('waits for a new item with the id of a removed one', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      queue.add(1, id: 'a');
      final first = queue.waitFor('a');
      final waited = <Future<QueueItem<int>>>[];
      // Moves the item to the back of the queue, under the same id.
      queue.onUpdate.listen((snapshot) {
        if (snapshot.event == QueueEvent.itemRemoved) {
          queue.add(2, id: 'a');
          waited.add(queue.waitFor('a'));
        }
      });

      queue
        ..removeById('a')
        ..start();

      expect((await first).data, 1);
      final second = await waited.single;
      expect(second.data, 2);
      expect(second.status, QueueItemStatus.completed);
    });
  });

  test('toString describes the queue, its items and its snapshots', () async {
    final queue = QueueIt<int>(itemHandler: (item) => throw Exception('oops'));
    addTearDown(queue.dispose);
    final snapshots = <QueueSnapshot<int>>[];
    queue.onUpdate.listen(snapshots.add);
    queue
      ..add(1)
      ..start();
    await queue.running;

    expect(queue.toString(), contains('Items: [1]'));
    expect(queue.items().single.toString(), contains('Error: Exception: oops'));
    expect(snapshots.first.toString(), contains('Event: itemAdded'));
    expect(queue.items().single.summaryTableLine, startsWith('failed'));
  });

  group('QueueItemsExtension', () {
    test('filters by status and measures progress', () async {
      final queue = QueueIt<int>(itemHandler: (item) {
        if (item.data == 2) throw Exception('failed');
      });
      addTearDown(queue.dispose);
      for (var i = 1; i <= 4; i++) {
        queue.add(i);
      }
      expect(queue.items().progress, 0);
      queue.cancelById(queue.items().last.id);
      expect(queue.items().progress, 0.25);

      queue.start();
      await queue.running;

      final items = queue.items();
      expect(items.completed.map((item) => item.data), [1, 3]);
      expect(items.failed.map((item) => item.data), [2]);
      expect(items.canceled.map((item) => item.data), [4]);
      expect(items.pending, isEmpty);
      expect(items.processing, isEmpty);
      expect(items.progress, 1);
      expect(<QueueItem<int>>[].progress, 1);
      expect(items.summary, contains('Failed: 1'));
      // ignore: deprecated_member_use_from_same_package
      expect(items.cancelled, items.canceled);
    });

    test('rounds the progress in the summary', () {
      final items = [
        for (var i = 0; i < 7; i++)
          QueueItem(
            data: i,
            batchId: 'batch',
            status: i < 2 ? QueueItemStatus.completed : QueueItemStatus.pending,
          ),
      ];

      expect(items.summary, contains('Progress: 29%'));
    });
  });
}
