# QueueIt

[![Pub Version](https://img.shields.io/pub/v/queue_it?label=queue_it)](https://pub.dev/packages/queue_it)
[![codecov](https://codecov.io/gh/sharpsan/queue_it_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/queue_it_library)

QueueIt makes dealing with queues in your Flutter and Dart apps easy, like uploading or downloading
files a few at a time.

## Features

- Queue management: Easily add, cancel and remove items.
- Event listeners: Listen for updates to the queue and receive snapshots.
- Concurrency: Control the number of items processed simultaneously.
- Retries: Automatically retry failed items.
- Progress: See each item's status and how much is done.
- Flutter: Rebuild your widgets when the queue changes, with
  [flutter_queue_it](https://pub.dev/packages/flutter_queue_it).

## Getting started

```sh
dart pub add queue_it
```

QueueIt requires Dart 3.5 or later.

## Usage

Here's a basic example of how to use QueueIt:

```dart
// lib/main.dart
import 'package:queue_it/queue_it.dart';

Future<void> main() async {
  final queue = QueueIt<int>(
    parallel: 1,
    retries: 3,
    itemHandler: (item) async {
      print('Handling item: ${item.data}');

      /// Fake processing time
      await Future<void>.delayed(const Duration(seconds: 1));
    },
  );
  queue.onUpdate.listen((snapshot) {
    print('Queue updated: ${snapshot.event.name}');
  });

  /// Add some items to the queue
  queue.add(1);
  queue.add(2);
  queue.add(3);

  /// Start processing the queue
  queue.start();

  /// You can continue adding more items to the queue after it starts processing
  queue.add(4);
  queue.add(5);

  /// Wait for every item to be processed
  await queue.running;
  queue.dispose();
}
```

For Flutter projects you will want to use [flutter_queue_it](https://pub.dev/packages/flutter_queue_it), which listens to queue changes and rebuilds your widget tree:

```dart
QueueItWidget(
  queue: _queue,
  builder: (context, snapshot) {
    /// `builder` will be called each time the queue updates
    final items = _queue.items().toList();
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text('Item status: ${item.status.name}'),
        );
      },
    );
  },
);
```

### Starting and stopping

`start()` processes items in the order they were added, `parallel` at a time. By default the queue
stops by itself once it runs out of items, whether they were processed, canceled or removed, and
items added after that wait for the next `start()`. If you start a queue with no items, it waits for
its first one.

```dart
/// Keep the queue running, so items added later are processed right away
queue.start(stopAutomatically: false);

/// Stop starting new items. Items being processed will finish, and pending items
/// wait for the next `start()`
queue.stop();

/// Completes once the queue has stopped and its items have finished
await queue.running;
```

`queue.isStarted` tells you whether the queue is started, and `queue.isProcessing` whether it's
working through items.

### Item statuses

Every item has a `status`:

- `pending`: Waiting to be processed, for the first time or for a retry.
- `processing`: The item handler is running.
- `completed`: The item handler returned.
- `failed`: The item handler threw, and there are no retries left.
- `canceled`: Canceled with `cancel`, `cancelById` or `cancelAll`.
- `removed`: Removed from the queue with `remove`, `removeById` or `removeAll`.

Only the queue changes an item, so `status`, `error` and `stackTrace` are read-only. To change
what happens to an item, use the queue's methods, or `nextStatus` from the item handler.

Items also record when they got to each status (`queuedAt`, `startedProcessingAt`, `completedAt`,
`failedAt`, `canceledAt` and `removedAt`), and any list of items has some helpers:

```dart
final items = queue.items();

/// Items with a given status
print(items.failed.length);

/// How much of the work is done, from 0 to 1
print(items.progress);

/// A count of the items in each status
print(items.summary);
```

### Retries

When the item handler throws, the item is retried up to `retries` times. Retries go ahead of the
other pending items, in the order they're due. Once there are no retries left the item is
`failed`, and `item.error` and `item.stackTrace` tell you why.

```dart
final queue = QueueIt<Uri>(
  retries: 3,

  /// Wait 1, 2, then 4 seconds before each retry. Other items keep
  /// processing in the meantime
  retryDelay: (item, retry) => Duration(seconds: 1 << (retry - 1)),

  /// Only retry errors that might go away
  retryIf: (item, error) => error is! FormatException,
  itemHandler: (item) => download(item.data),
);
```

The item handler can also set `item.nextStatus` to choose what happens to the item when it returns,
for example `QueueItemStatus.pending` to process it again later. And a listener can cancel an item
in its `failed` update, so it isn't retried.

### Canceling and removing items

```dart
final id = queue.add(6);

/// The item won't be processed
queue.cancelById(id);

/// Same as canceling, and the item is also taken out of the queue
queue.removeById(id);
```

An item that's already processing can't be interrupted, so its handler keeps running, and counts
towards `parallel` until it returns, but QueueIt ignores the result and won't retry it. If your
handler does a lot of work, it can check `item.status` to stop early. `cancel` and `remove` take
an item instead of an id, including the copies you get in snapshots, and `cancelAll` and
`removeAll` work on every item.

### Waiting for an item

`waitFor` completes with a copy of the item once it's completed, canceled or removed, or failed
with no retries left. Make sure the queue is started, or the item won't be processed:

```dart
final item = await queue.waitFor(queue.add(7));
if (item.status == QueueItemStatus.failed) {
  print('Item failed: ${item.error}');
}
```

### Listening for updates

`onUpdate` sends a `QueueSnapshot` every time the queue changes:

```dart
queue.onUpdate.listen((snapshot) {
  /// What happened, such as `itemAdded` or `stoppedProcessing`
  print(snapshot.event.name);

  /// A copy of the item the update is about, if there is one
  final item = snapshot.eventItem;

  /// You can call the queue from a listener, like stopping at the first failure
  if (item?.status == QueueItemStatus.failed) queue.stop();
});
```

Every failed attempt sends a `failed` update, including the ones that will be retried.
`snapshot.willRetry` is true for those, and false once an item has failed for good. New events may
come in minor versions, so in a `switch` over `snapshot.event`, handle the ones you need and use a
default case for the rest.

`snapshot.items` holds the items of the current batch. These are the queue's own items, so they keep
changing after the update. If you need them as they were at the time, create the queue with
`deepCopyItemsInSnapshot: true`, but copying them costs time on every update, especially for big
batches. Counting the queue's own items is quick however many there are: `length`, `progress`,
`summary` and counts like `items.completed.length`.

### Batches

Items added while the queue still has unfinished items share a `batchId`. Once every item has
finished, the next item you add starts a new batch. `queue.currentBatchItems` gives you the current
batch, `queue.items()` every item, and `queue.items(batchId)` a single batch. Finished items stay in
the queue until you remove them.

### Item ids

`add` returns the item's id. It's a UUID, unless you pass your own with `queue.add(data, id: 'my-id')`.
Ids must be unique within the queue. Set `useFriendlyIds: true` for readable ids like
`big wizard cat`. There are only a few hundred of those, so the id of a removed item can come up
again. `queue.itemById(id)` gives you the item, or null if the queue doesn't have it.

### Disposing

Call `dispose()` when you're done with a queue. It stops the queue and closes `onUpdate`. Handlers
that are still running aren't interrupted, but their results are ignored, and `waitFor` futures
that are still waiting fail with a `StateError`.

For a more in-depth look at how to use QueueIt, check out the
[example project](https://pub.dev/packages/queue_it/example).

## Migrating from 0.10

- An item's `status`, `error` and `stackTrace` are now read-only. To cancel or remove an item,
  use the queue's `cancel` and `remove` methods, and to choose what happens to an item when its
  handler returns, set `item.nextStatus` in the handler. To fail an item with an error, throw it
  from the handler.
- Items you make yourself, for example in tests, get their status from the constructor, which
  records when they got there, and their `error` and `stackTrace` from `copyWith`:
  `QueueItem(data: 'a', batchId: 'b', status: QueueItemStatus.failed).copyWith(error: e)`.
- `items.cancelled` and `OnUpdateCallback`, deprecated in 0.10.0, are gone. Use `items.canceled`,
  and listen to `queue.onUpdate` for updates. If you used `OnUpdateCallback` as a type, declare
  your own:
  `typedef OnUpdateCallback<T> = void Function(QueueItemStatus status, QueueItem<T> item);`
- `nextStatus` only counts when it's set while the item is processing, usually by its handler. A
  value set before then, for example on a pending item, is ignored.
- `QueueEvent.cancelledAll` is now `QueueEvent.canceledAll`, and `items.summary` says `Canceled`
  instead of `Cancelled`.
- `retryDelay` and `retryIf` now get the item first: `retryDelay: (item, retry) => ...` and
  `retryIf: (item, error) => ...`.

## Migrating from 0.9

These come on top of the changes from 0.10 above.

- Items that run out of retries are now `failed` instead of `canceled`, and `item.error` and
  `item.stackTrace` hold the last error. If you looked for canceled items to find failures, look
  for failed ones instead.
- `add` throws an `ArgumentError` if the queue already has an item with that id. Use `hasItemById`
  to check first.
- `add` and `start` throw a `StateError` once the queue is disposed.
- `cancel` only cancels pending and processing items, and returns `false` for items that have
  already finished.
- The first item added after every item has finished starts a new batch, instead of only when the
  queue is empty.
- Canceled and removed items now stay that way, even if they were processing at the time.
- `onUpdate` listeners can now call the queue. If you delayed those calls to get around the
  `Cannot fire new event` error, you don't need to anymore.
- `items.cancelled` is now `items.canceled`, and the unused `OnUpdateCallback` is gone.
- QueueIt now requires Dart 3.5 or later.

If QueueIt is useful to you, give it a like on [pub.dev](https://pub.dev/packages/queue_it).

## License

QueueIt is licensed under the [MIT License](https://github.com/sharpsan/queue_it_library/blob/main/queue_it/LICENSE).
