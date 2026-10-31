# flutter_queue_it example

An image queue built with `QueueItWidget`. Each item is the URL of a random image from
[Lorem Picsum](https://picsum.photos). The queue processes three items at a time, retries a failed
item up to three times, and gives items readable ids instead of UUIDs.

The screen shows:

- a progress bar while items are processing,
- each item with its image, its timestamps and an icon for its status,
- a button that starts the queue, stops it while it runs, or clears it once everything is done,
- a button that adds an image.

Swipe an item away to remove it from the queue. A listener on `onUpdate` also logs every queue
event with `dart:developer`'s `log`, which shows in your IDE's debug console and in DevTools.

## Run it

From this folder:

```sh
flutter run
```

The code is in [lib/main.dart](lib/main.dart).
