# flutter_queue_it

[![Pub Version](https://img.shields.io/pub/v/flutter_queue_it?label=flutter_queue_it)](https://pub.dev/packages/flutter_queue_it)
[![codecov](https://codecov.io/gh/sharpsan/queue_it_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/queue_it_library)

> Flutter integration for [queue_it](https://pub.dev/packages/queue_it).

**`QueueItWidget`** rebuilds whenever a `QueueIt` queue changes, so your UI can show what's
waiting, what's processing and how far along the queue is.

## Install

```sh
flutter pub add queue_it flutter_queue_it
```

`queue_it` provides the queue and this package provides the widget. Both need Dart 3.5 and
Flutter 3.24 or later.

## Quick start

This app processes "uploads" two at a time and lists them with their status:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_queue_it/flutter_queue_it.dart';
import 'package:queue_it/queue_it.dart';

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
- **Read state from the queue.** `queue.items()`, `queue.isStarted` and `queue.isProcessing` are
  always current, including on the first build. Use the snapshot for the event behind a rebuild:
  `snapshot.event` says what happened, and `snapshot.eventItem` is a copy of the item involved,
  taken at that moment.
- **`snapshot.items` is live by default.** It holds the items of the queue's current batch. Unless
  the queue was created with `deepCopyItemsInSnapshot: true`, those are the queue's own items, so
  they show each item's current status, not its status at the time of the event. Copying them for
  every event costs time on large queues.

## Acting on every event

The builder isn't the place to log or notify: it skips events, and Flutter can call it at other
times. Listen to `queue.onUpdate` instead. In the quick start's `_UploadsPageState`, this shows a
message each time the queue runs out of work:

```dart
late final StreamSubscription<QueueSnapshot<String>> _subscription;

@override
void initState() {
  super.initState();
  _subscription = _queue.onUpdate.listen((snapshot) {
    if (snapshot.event == QueueEvent.stoppedProcessing && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All uploads processed')),
      );
    }
  });
}

@override
void dispose() {
  _subscription.cancel();
  _queue.dispose();
  super.dispose();
}
```

`StreamSubscription` comes from `dart:async`.

## Owning the queue

- The widget never starts, stops or disposes the queue. Keep the queue somewhere that outlives
  rebuilds, such as a `State`, and call `queue.dispose()` when you're done with it.
- Any number of `QueueItWidget`s can listen to the same queue, such as a list and a counter in the
  app bar.
- If a rebuild passes a different queue, the widget listens to the new one. Until the new queue
  changes, the builder still receives the old queue's last snapshot.

## Learn more

- [queue_it](https://pub.dev/packages/queue_it) covers the queue itself: running items in
  parallel, retries, item statuses and batches.
- The [example app](https://pub.dev/packages/flutter_queue_it/example) queues images, processes
  three at a time with retries, and shows progress, each item's status, and start and stop
  buttons.
- The [API reference](https://pub.dev/documentation/flutter_queue_it/latest/) documents
  `QueueItWidget`.
