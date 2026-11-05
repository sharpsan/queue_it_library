## 0.10.1

* Requires queue_it 0.10.1, which fixes `waitFor`, batches and `dispose` in a few cases where
  listeners call the queue. See its changelog.
* Fix: `QueueItWidget` no longer throws when the queue changes while Flutter is building, laying
  out or disposing widgets, for example from a widget's `initState` or `dispose`. It rebuilds
  right after that frame.
* Fix: `QueueItListener` stops calling the listener as soon as it's being removed, so the listener
  never gets a context it can't use.
* Docs: the README's progress bar shows the current batch, and its "All uploads processed"
  message no longer shows when the queue is stopped early.
* Example: a canceled or removed image is no longer downloaded and shown anyway.

## 0.10.0

* Requires Dart 3.5 and Flutter 3.24 or later. The previous Flutter minimum (1.17) was lower
  than the Dart 3.3 requirement allowed.
* Requires queue_it 0.10.0, which fixes canceling, removing and stopping, lets `onUpdate`
  listeners call the queue, and has a few breaking changes. See its changelog.
* Add: `QueueItListener`, which calls back for every event without rebuilding.
* Add: `QueueItWidget.buildWhen`, to rebuild only for some events.
* Exports `package:queue_it/queue_it.dart`, so `flutter_queue_it` is the only dependency and import
  you need. If you import both, remove the `queue_it` import, or the analyzer reports it as
  unnecessary.
* Documented `QueueItWidget`: when the builder runs, what the snapshot holds, and who owns the
  queue.
* Rewrote the README with an install step, a complete example, how rebuilds work, and a section on
  migrating from 0.9.
* Added widget tests.
* Example: regenerated the platform projects for current Flutter, and the app now downloads the
  images for real, with simulated failures, retries after a delay, cancel buttons, and a message
  for each image that runs out of retries.

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
