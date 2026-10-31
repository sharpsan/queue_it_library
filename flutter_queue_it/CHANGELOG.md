## 0.11.0

* Requires queue_it 0.11.0, which fixes canceling, removing and stopping, and lets `onUpdate`
  listeners call the queue.
* Add: `QueueItListener`, which calls back for every event without rebuilding.
* Add: `QueueItWidget.buildWhen`, to rebuild only for some events.
* Exports `package:queue_it/queue_it.dart`, so `flutter_queue_it` is the only dependency and import
  you need. If you import both, remove the `queue_it` import, or the analyzer reports it as
  unnecessary.
* Example: downloads the images for real, with simulated failures, retries after a delay, cancel
  buttons, and a message for each image that runs out of retries.

## 0.10.0

* Requires Dart 3.5 and Flutter 3.24 or later. The previous Flutter minimum (1.17) was lower
  than the Dart 3.3 requirement allowed.
* Requires queue_it 0.10.0.
* Documented `QueueItWidget`: when the builder runs, what the snapshot holds, and who owns the
  queue.
* Rewrote the README with an install step, a complete quick start, and how rebuilds work.
* Added widget tests.
* Example: regenerated the platform projects for current Flutter, allowed network images on
  Android release builds and macOS, and fixed a crash when two queued images had the same URL.

## 0.9.0

* Fix dependency constraints

## 0.0.4

* Updated example project

## 0.0.3

* Added example to README.md

## 0.0.2

* Fix: updated repo urls

## 0.0.1

* Initial version.
