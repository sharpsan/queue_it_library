# flutter_queue_it example

A photo uploader built with `QueueItWidget` and `QueueItListener`. It uploads three photos at a
time and shows how each one is going.

The uploads are simulated, so the example runs without a server, and about a third of them fail on
purpose to show off retries. A failed upload is retried twice, after waiting 1 and then 2 seconds,
and you get a message if it still fails. The photos come from [Lorem Picsum](https://picsum.photos).

You can:

- Add six photos at a time.
- Pause and resume the uploads.
- Cancel a photo by tapping its cross, and try a failed or canceled one again.
- Swipe a photo away to remove it.
- Clear the finished photos.

QueueIt doesn't interrupt a handler that's already running, so when you cancel or remove a photo,
the example stops its upload itself.

### Running the example

The example needs Flutter 3.47 or later. From this folder:

```sh
flutter run
```

Check out [lib/main.dart](https://github.com/sharpsan/queue_it_library/blob/main/flutter_queue_it/example/lib/main.dart)
to see how it works.
