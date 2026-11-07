# flutter_queue_it example

An image downloader built with `QueueItWidget` and `QueueItListener`. It downloads random images
from [Lorem Picsum](https://picsum.photos), three at a time.

To show off retries, about a third of the downloads fail on purpose. A failed download is retried
twice, after waiting 1 and then 2 seconds, and you get a message if it still fails.

You can:

- Add five images at a time.
- Start and stop the queue.
- Cancel a waiting or downloading image by tapping its cross.
- Swipe an image away to remove it from the queue.
- Remove all the finished images.

### Running the example

The example needs Flutter 3.47 or later. From this folder:

```sh
flutter run
```

Check out [lib/main.dart](https://github.com/sharpsan/queue_it_library/blob/main/flutter_queue_it/example/lib/main.dart)
to see how it works.
