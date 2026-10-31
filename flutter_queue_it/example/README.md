# flutter_queue_it example

An image downloader built with `QueueItWidget` and `QueueItListener`. Each item is the URL of a
random image from [Lorem Picsum](https://picsum.photos). The queue downloads three images at a
time and gives items readable ids instead of UUIDs. To show retries, about a third of the attempts
fail on purpose: a failed download is retried twice, after one and then two seconds.

The screen shows:

- a progress bar for the current batch while the queue is processing,
- each image with its status, its retries and its last error,
- a button that starts the queue and stops it,
- a button that adds five images,
- a button that removes the finished images,
- a message when an image runs out of retries.

Tap the cross on a waiting or downloading image to cancel it, or swipe an image away to remove it
from the queue. The start and stop button uses `buildWhen` to rebuild only when the queue starts
or stops.

## Run it

From this folder:

```sh
flutter run
```

The code is in [lib/main.dart](lib/main.dart).
