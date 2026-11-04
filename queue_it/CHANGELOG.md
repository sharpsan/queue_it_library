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
