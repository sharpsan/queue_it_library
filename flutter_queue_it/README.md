# flutter_queue_it

[![Pub Version](https://img.shields.io/pub/v/flutter_queue_it?label=flutter_queue_it)](https://pub.dev/packages/flutter_queue_it)
[![codecov](https://codecov.io/gh/sharpsan/queue_it_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/queue_it_library)

> Flutter integration for [queue_it](https://pub.dev/packages/queue_it).

**`QueueItWidget`** rebuilds whenever a `QueueIt` queue changes, so your UI can show what's
waiting, what's processing and how far along the queue is. **`QueueItListener`** calls back for
every event, to show a message or log, without rebuilding.

## Install

```sh
flutter pub add flutter_queue_it
```

`queue_it` provides the queue and this package provides the widgets. This package exports
`queue_it`, so `package:flutter_queue_it/flutter_queue_it.dart` is the only import you need. It
needs Dart 3.5 and Flutter 3.24 or later.

## Quick start

This app processes "uploads" two at a time and lists them with their status:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_queue_it/flutter_queue_it.dart';

void main() => runApp(const MaterialApp(home: UploadsPage()));

class UploadsPage extends StatefulWidget {
  const UploadsPage({super.key});

  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

class _UploadsPageState extends State<UploadsPage> {
  final _queue = QueueIt<String>(
    parallel: 2,
    itemHandler: (item) async {
      // Do the work for item.data here, such as uploading a file.
      await Future<void>.delayed(const Duration(seconds: 1));
    },
  );
  var _count = 0;

  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uploads')),
      body: QueueItWidget<String>(
        queue: _queue,
        builder: (context, snapshot) {
          final items = _queue.items().toList();
          return Column(
            children: [
              if (_queue.isProcessing)
                LinearProgressIndicator(value: items.progress),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(items[index].data),
                    trailing: Text(items[index].status.name),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _queue
          ..add('photo_${++_count}.jpg')
          ..start(),
        tooltip: 'Add upload',
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

The page's `State` owns the queue and disposes of it. The builder reads the items from the queue
each time it runs. The button adds an item and starts the queue, which stops by itself once every
item is processed; starting a queue that's already running does nothing.

## How QueueItWidget rebuilds

- **The first build gets a null snapshot.** The queue doesn't replay events sent before the widget
  started listening, so `snapshot` stays null until the queue next changes, even if it already
  has items.
- **Each change schedules a rebuild.** Changes in the same frame cause a single rebuild with the
  latest snapshot, so the builder doesn't see every event.
- **`buildWhen` skips events.** It gets each event's snapshot and returns whether to rebuild, for
  example to rebuild a counter only when items are added or removed.
- **Read state from the queue.** `queue.items()`, `queue.isStarted` and `queue.isProcessing` are
  always current, including on the first build. Use the snapshot for the event behind a rebuild:
  `snapshot.event` says what happened, and `snapshot.eventItem` is a copy of the item involved,
  taken at that moment.
- **`snapshot.items` is live by default.** It holds the items of the queue's current batch. Unless
  the queue was created with `deepCopyItemsInSnapshot: true`, those are the queue's own items, so
  they show each item's current status, not its status at the time of the event. Copying them for
  every event costs time on large queues.

## Acting on every event

The builder isn't the place to show a message or log: it skips events, and Flutter can call it at
other times. Wrap the part of the tree that needs it in a `QueueItListener`, which calls its
listener once for every event, in order. In the quick start, this shows a message each time the
queue runs out of work:

```dart
body: QueueItListener<String>(
  queue: _queue,
  listener: (context, snapshot) {
    if (snapshot.event == QueueEvent.stoppedProcessing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All uploads processed')),
      );
    }
  },
  child: QueueItWidget<String>(
    // ...
  ),
),
```

The listener runs synchronously, as the queue sends the event, and it can call the queue.

## Owning the queue

- The widgets never start, stop or dispose of the queue. Keep the queue somewhere that outlives
  rebuilds, such as a `State`, and call `queue.dispose()` when you're done with it.
- Any number of `QueueItWidget`s and `QueueItListener`s can listen to the same queue, such as a
  list and a counter in the app bar.
- If a rebuild passes a different queue, the widgets listen to the new one. Until the new queue
  changes, a `QueueItWidget`'s builder still receives the old queue's last snapshot.

## Learn more

- [queue_it](https://pub.dev/packages/queue_it) covers the queue itself: running items in
  parallel, retries, item statuses and batches.
- The [example app](https://pub.dev/packages/flutter_queue_it/example) downloads images three at
  a time, with simulated failures, retries after a delay, progress, cancel and remove, and a
  message for each image that runs out of retries.
- The [API reference](https://pub.dev/documentation/flutter_queue_it/latest/) documents
  `QueueItWidget` and `QueueItListener`.
