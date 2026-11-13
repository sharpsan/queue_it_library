## 1.0.0

* flutter_queue_it's API is now stable: breaking changes only come with a new major version. New
  `QueueEvent`s, members and optional parameters may still come in minor versions.
* BREAKING CHANGE: requires queue_it 1.0.0, where an item's `status`, `error` and `stackTrace` are
  read-only, `items.cancelled` and `OnUpdateCallback` are gone, `QueueEvent.cancelledAll` is
  now `canceledAll`, and `retryDelay` and `retryIf` get the item. See its changelog.
* Fix: whatever a `QueueItListener`'s listener throws is reported to `FlutterError.onError`, like
  errors in other widgets. Before, that only happened for events sent while Flutter was building,
  and the others went to the zone. If `FlutterError.onError` throws, the listener still gets the
  next events, and the frame's other callbacks still run.
* Fix: in release builds, queue changes made while Flutter builds the app's first widgets now
  wait for the end of that frame, as they do in debug builds. Before, a `QueueItListener` was
  called in the middle of the build, and a `QueueItWidget` whose builder changed the queue
  didn't rebuild for it.
* Docs: the README's example imports the `material_ui` package, which replaces
  `package:flutter/material.dart`, deprecated in Flutter 3.50.
* Docs: the README and pub.dev page show the example app.
* Example: the example app is now a photo uploader. It uses `material_ui`, so it needs Flutter 3.47
  or later, and it builds with Flutter 3.50. The package itself still supports Flutter 3.24.

## 0.10.1

* Requires queue_it 0.10.1, which retries items in order and fixes `waitFor`, batches and `dispose`
  in a few cases where listeners call the queue. See its changelog.
* Fix: `QueueItWidget` no longer throws when the queue changes while Flutter is building, laying
  out or disposing widgets, for example from a widget's `initState` or `dispose`. It rebuilds
  right after that frame.
* Fix: `QueueItListener` calls the listener right after the frame for updates sent while Flutter is
  building or disposing widgets, so the listener can use its context to show a SnackBar, and it
  isn't called once the widget is being removed. When it's moved with a `GlobalKey`, the updates
  sent during the move reach its listener in order, right after that frame, unless it's given
  another queue at the same time.
* Docs: the README's progress bar shows the current batch, and its "All uploads processed"
  message no longer shows when the queue is stopped early.
* Example: a canceled or removed image is no longer downloaded and shown anyway, two images swiped
  away one after the other are both removed, and a download gives up after 30 seconds.

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
