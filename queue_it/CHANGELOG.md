## 1.0.0

* QueueIt's API is now stable: breaking changes only come with a new major version.
* BREAKING CHANGE: an item's `status`, `error` and `stackTrace` are now read-only, so only the
  queue changes them. To cancel or remove an item, use the queue's `cancel` and `remove` methods,
  and to choose what happens to an item when its handler returns, set `QueueItem.nextStatus`.
* BREAKING CHANGE: removed `items.cancelled` and `OnUpdateCallback`, deprecated in 0.10.0. Use
  `items.canceled`, and listen to `QueueIt.onUpdate` for updates.

## 0.10.1

* Fix: `waitFor` gives the item as it finished, even when a listener then removes the item or
  disposes the queue, or adds a new item with the same id.
* Fix: `waitFor` fails with a `StateError` when it's called after `dispose` for an item that
  hasn't finished, instead of never completing.
* Fix: in the `failed` update of an attempt that will be retried, `waitFor` waits for the retry,
  and `cancel` cancels the item instead of returning false.
* Fix: disposing the queue from a listener as an item fails no longer leaves its retry timer
  running.
* Fix: items waiting to be retried are retried in the order they're due, instead of the newest
  first.
* Fix: once a listener disposes the queue, other listeners' calls to it send no more updates, as
  after any other `dispose`.
* Fix: `running` completes when the queue stops with no handlers running, even if a listener
  starts it again right away.
* Fix: an item being retried stays in its batch when a listener adds an item during its `failed`
  or `pending` update, and a canceled item whose handler is still running no longer keeps its
  batch open.
* Fix: removed items are let go right away, instead of staying in memory while the queue is
  stopped.
* Fix: an item added by a `stoppedProcessing` listener is processed, instead of waiting for the
  next `start`.
* Fix: a queue that stops automatically also stops when its items are all canceled or removed
  before it gets to them, so `running` completes.
* Fix: a queue that a `stoppedProcessing` listener stops and starts again waits for new items,
  instead of stopping right away.
* Fix: a queue started while only the handlers of canceled items are running waits for new items,
  instead of stopping when those handlers return.
* Fix: an item's handler no longer starts when a listener disposes the queue as the item starts
  processing.
* Fix: after `dispose`, `isProcessing` becomes false once the running handlers return, and
  listeners can't start the queue again.
* Fix: removing items one at a time no longer slows down as the queue grows (80,000 items took
  39 s; now well under a second).
* Fix: calling the queue after `dispose` no longer throws while an `onUpdate` listener is paused,
  for example by `asyncMap` or an `await for` loop that's awaiting.
* Fix: the constructor throws an `ArgumentError` for a `parallel` below 1 or negative `retries`.
  These were only asserts, so a release build with `parallel: 0` never processed anything.
* Fix: a long run of items whose handler throws right away, without being `async`, no longer
  overflows the stack and leaves the queue stuck.
* Fix: `summary` rounds the progress, and `progress` is only 1 once every item has finished,
  instead of rounding up to 1 with items left.
* Fix: with `deepCopyItemsInSnapshot`, each update costs time in proportion to the current batch,
  as documented, instead of to every item the queue holds. `currentBatchItems` is faster too when
  the queue keeps the items of earlier batches.
* Docs: an error thrown by `retryIf` or `retryDelay` is reported as an uncaught error, and the item
  isn't retried.
* Docs: corrections about which statuses are final, what snapshots copy, what `retryDelay` is
  called with, and what `summary` counts. `nextStatus = pending` tries again before timers and I/O
  get to run, so a handler waiting for something should await it first.

## 0.10.0

* Requires Dart 3.5 or later.
* BREAKING CHANGE: an item whose retries run out is now `failed`, not `canceled`, and keeps the
  error in `QueueItem.error` and `QueueItem.stackTrace`.
* BREAKING CHANGE: `add` throws an `ArgumentError` for an id the queue already has, and `add` and
  `start` throw a `StateError` once the queue is disposed.
* BREAKING CHANGE: `cancel` only cancels pending and processing items, and returns false for the
  rest.
* BREAKING CHANGE: a new batch starts when an item is added after every item has finished, as
  `QueueItem.batchId` always said, instead of only when the queue is empty.
* Fix: canceling an item while it's processing no longer gets overwritten when its handler
  returns, and a canceled item is no longer retried.
* Fix: removed items, including after `removeAll`, are no longer processed. Their status becomes
  `removed`.
* Fix: `onUpdate` listeners can call the queue (to add, cancel, stop and so on) without a
  `Bad state: Cannot fire new event` error.
* Fix: after `stop`, `running` completes once the running items finish, `isProcessing` becomes
  false and `stoppedProcessing` is sent.
* Fix: stopping and starting the queue at once no longer runs more than `parallel` items.
* Fix: `cancel`, `remove` and `hasItem` find the queue's item by id, so they work with the copies
  in snapshots.
* Fix: `nextStatus = processing` fails the item instead of leaving the queue running forever, and
  `nextStatus = canceled` sends one event instead of two.
* Fix: processing time no longer grows with the number of finished items in the queue.
* Fix: the README's link to flutter_queue_it.
* Add: `retryDelay` and `retryIf`.
* Add: `waitFor(id)`, which completes when an item finishes.
* Add: the `canceled` extension getter; `cancelled` is deprecated, and so is the unused
  `OnUpdateCallback`.
* Add: pub.dev topics.
* Docs: the whole API is documented, and the README covers more of the queue, with a section on
  migrating from 0.9.

## 0.9.0

* Fix dependency constraints

## 0.0.4

* Improve: disable deep-copying items in snapshots by default, greatly improving performance.  This can be controlled by setting `deepCopyItemsInSnapshot`.

## 0.0.3

* Fix: improve order of operations when using parallel processing
* Fix: retries
* Add: queue date fields
* Add: toString() summaries for queue, snapshot, and item

## 0.0.2

* Fix: updated repo urls
* BREAKING CHANGE: changed `concurrentOperations` to `parallel`
* BREAKING CHANGE: changed `retryLimit` to `retries`
* Add: added example project to queue_it
* Improve: only send snapshot events when there are subscribers
* Feat: added option `useFriendlyIds` to make ID's more readable (experimental)

## 0.0.1

* Initial version.
