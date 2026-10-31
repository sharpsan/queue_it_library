# queue_it

[![Pub Version](https://img.shields.io/pub/v/queue_it?label=queue_it)](https://pub.dev/packages/queue_it)
[![codecov](https://codecov.io/gh/sharpsan/queue_it_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/queue_it_library)

Queue up work and process it a few items at a time, with retries, item statuses and a stream of
snapshots you can show in a UI.

- **Parallel processing**: up to `parallel` items at once, in the order they were added.
- **Retries**: retry failed items, after a delay if you like, and keep the error of the last
  attempt.
- **Statuses**: every item is pending, processing, completed, failed, canceled or removed, with
  the time it got there.
- **Snapshots**: listen to every change, with the queue's state and progress.
- **Flutter**: [flutter_queue_it](https://pub.dev/packages/flutter_queue_it) rebuilds widgets when
  the queue changes.

## Install

```sh
dart pub add queue_it
```

It needs Dart 3.5 or later.

## Quick start

```dart
// lib/main.dart
import 'package:queue_it/queue_it.dart';

Future<void> main() async {
  final queue = QueueIt<String>(
    parallel: 2,
    retries: 2,
    itemHandler: (item) async {
      // Do the work for item.data here, such as downloading a file.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );
  queue.onUpdate.listen((snapshot) {
    final item = snapshot.eventItem;
    print(item == null
        ? snapshot.event.name
        : '${item.data}: ${item.status.name}');
  });

  for (final file in ['a.txt', 'b.txt', 'c.txt']) {
    queue.add(file);
  }
  queue.start();
  await queue.running;

  print(queue.items().summary);
  queue.dispose();
}
```

## Processing

- `start()` processes the pending items, oldest first, `parallel` at a time. Items added while the
  queue is started are processed when their turn comes.
- By default, the queue stops by itself once it has processed every item, and items added after
  that wait for the next `start()`. A queue started with no items waits for its first one.
  `start(stopAutomatically: false)` keeps the queue waiting for items until you call `stop()`.
- `stop()` keeps the queue from starting more items. Items being processed finish; pending items
  wait for the next `start()`.
- `running` is a future that completes when the queue has stopped and the items it was processing
  have finished.
- `isStarted` says whether the queue is started, and `isProcessing` whether it's working through
  items.

## Item statuses

| Status | Meaning |
|---|---|
| `pending` | Waiting to be processed, for the first time or for a retry. |
| `processing` | The item handler is running. |
| `completed` | The handler returned. |
| `failed` | The handler threw, and no retries are left. |
| `canceled` | Canceled by `cancel`, `cancelById` or `cancelAll`. |
| `removed` | Removed by `remove`, `removeById` or `removeAll`, so no longer in the queue. |

Each item records when it got to each status: `queuedAt`, `startedProcessingAt`, `completedAt`,
`failedAt`, `canceledAt` and `removedAt`. `queue.items()` lists the items in the order they were
added, and `.pending`, `.processing`, `.completed`, `.failed`, `.canceled`, `.progress` and
`.summary` work on any list of items.

## Retries and errors

When the handler throws, the item is retried up to `retries` times, first in line. Each failed
attempt shows as `failed` and then `pending` again. When no retries are left, the item stays
`failed`, and `item.error` and `item.stackTrace` hold what the last attempt threw.

`retryDelay` waits before each retry, without holding up the other items, and `retryIf` decides
which errors are worth retrying:

```dart
final queue = QueueIt<Uri>(
  retries: 3,
  // Wait 1, 2, then 4 seconds.
  retryDelay: (retry) => Duration(seconds: 1 << (retry - 1)),
  // Bad input won't get better.
  retryIf: (error) => error is! FormatException,
  itemHandler: (item) => download(item.data),
);
```

The handler can also choose what happens to the item when it returns by setting
`item.nextStatus`, for example to process it again later.

## Canceling and removing

`cancel(item)` stops a pending item from being processed. An item that's processing can't be
interrupted, so its handler keeps running, but the queue ignores the outcome and doesn't retry it.
A handler doing long work can check `item.status` to stop early.

`remove(item)` does the same and also takes the item out of the queue. Both find the queue's item
by id, so a copy works too, and both have `ById` and `All` versions.

## Waiting for an item

`waitFor` completes with a copy of the item once it's completed, failed with no retries left,
canceled or removed:

```dart
final item = await queue.waitFor(queue.add('report.pdf'));
if (item.status == QueueItemStatus.failed) {
  print('report.pdf failed: ${item.error}');
}
```

## Listening

`onUpdate` is a broadcast stream with a `QueueSnapshot` for every change, sent synchronously:

- `event` says what happened, such as `itemAdded` or `stoppedProcessing`.
- `eventItem` is a copy of the item involved, taken at that moment.
- `isStarted`, `isProcessing` and the queue's start and stop times are as they were at the event.
- `items` holds the current batch. These are the queue's live items, which keep changing, unless
  the queue was created with `deepCopyItemsInSnapshot: true`. Copying costs time on every event,
  more so for big batches.

Listeners can call the queue. For example, to stop the queue at the first failure:

```dart
queue.onUpdate.listen((snapshot) {
  if (snapshot.eventItem?.status == QueueItemStatus.failed) queue.stop();
});
```

Every failed attempt sends a `failed` status, including ones that will be retried.

## Batches

Items added while the queue has unfinished items share a batch id, `item.batchId`. Once every item
has finished, the next item added starts a new batch. `queue.currentBatchItems` and each snapshot's
`items` hold the current batch, `queue.items()` holds every item, and `queue.items(batchId)` holds
one batch. Finished items stay in the queue until you remove them.

## Ids

Items get a UUID, or the id you pass to `add`, which must be unique in the queue.
`useFriendlyIds: true` gives readable ids such as `big wizard cat` instead.

## Disposing

Call `dispose()` when you're done with a queue. It stops the queue and closes `onUpdate`. Handlers
that are running aren't interrupted, but the queue ignores their outcome.

## License

queue_it is licensed under the
[MIT License](https://github.com/sharpsan/queue_it_library/blob/main/queue_it/LICENSE).
