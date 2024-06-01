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
