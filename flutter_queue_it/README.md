# flutter_queue_it


[![Pub Version](https://img.shields.io/pub/v/flutter_queue_it?label=flutter_queue_it)](https://pub.dev/packages/flutter_queue_it)
[![codecov](https://codecov.io/gh/sharpsan/queue_it_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/queue_it_library)

> Flutter integration with [queue_it](https://pub.dev/packages/queue_it).

Provides the **`QueueItWidget`** widget that listens to the queue and automatically
rebuilds on changes, and the **`QueueItListener`** widget that lets you react to every change
without rebuilding.

### Getting started

```sh
flutter pub add flutter_queue_it
```

flutter_queue_it exports queue_it, so it's the only package you need to add and import. It requires
Dart 3.5 and Flutter 3.24 or later.

### Example

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
  /// Keep the queue in your `State`, so it survives rebuilds
  final _queue = QueueIt<String>(
    parallel: 2,
    itemHandler: (item) async {
      /// Fake upload time
      await Future<void>.delayed(const Duration(seconds: 1));
    },
  );
  var _count = 0;

  @override
  void dispose() {
    /// The widgets never dispose of the queue, so do it here
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
          /// `builder` will be called each time the queue updates
          final items = _queue.items().toList();
          return Column(
            children: [
              /// The progress of the current batch: the uploads added since the
              /// queue last ran out of work
              if (_queue.isProcessing)
                LinearProgressIndicator(
                  value: _queue.currentBatchItems.progress,
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(item.data),
                      subtitle: Text('Item status: ${item.status.name}'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        /// Add an item and start the queue. The queue stops by itself once every
        /// item is processed, and starting it while it's running does nothing
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

Newer Flutter versions deprecate `package:flutter/material.dart` in favor of the
[material_ui](https://pub.dev/packages/material_ui) package. On Flutter 3.47 or later, add it with
`flutter pub add material_ui` and import `package:material_ui/material_ui.dart` instead.

### Rebuilding less often

Use `buildWhen` to only rebuild for the updates you care about:

```dart
QueueItWidget(
  queue: _queue,

  /// Only rebuild when the queue starts or stops
  buildWhen: (snapshot) =>
      snapshot.event == QueueEvent.startedQueue ||
      snapshot.event == QueueEvent.stoppedQueue,
  builder: (context, snapshot) {
    return Text(_queue.isStarted ? 'Running' : 'Stopped');
  },
);
```

### Reacting to every update

`builder` isn't the place to show a message or log something, because it can skip updates and
Flutter can call it at other times. Use `QueueItListener` instead:

```dart
QueueItListener(
  queue: _queue,
  listener: (context, snapshot) {
    /// `listener` will be called once for every update, without rebuilding.
    /// Processing also stops when the queue is stopped, so check that no
    /// uploads are left
    if (snapshot.event == QueueEvent.stoppedProcessing &&
        snapshot.items.pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All uploads processed')),
      );
    }
  },
  child: const UploadList(),
);
```

The listener can call the queue too. It's called as soon as the queue sends an update. Updates sent
while Flutter is building or disposing widgets, for example from a widget's `initState` or
`dispose`, reach the listener right after that frame, so it can still show a SnackBar. Once the
widget is being removed, the listener isn't called any more.

### Good to know

- The first build gets a null `snapshot`. The queue doesn't replay updates sent before the widget
  started listening, so read the current state from the queue itself: `queue.items()`,
  `queue.isStarted` and `queue.isProcessing` are always up to date.
- Updates sent in the same frame cause a single rebuild with the latest snapshot. Updates sent
  while Flutter is building, for example from a widget's `initState` or `dispose`, rebuild the
  widget right after that frame.
- `snapshot.event` tells you what happened, and `snapshot.eventItem` is a copy of the item the
  update is about, taken at that moment. `snapshot.items` holds the queue's own items, so they show
  each item's current status (and leave out the ones removed since), unless the queue was created
  with `deepCopyItemsInSnapshot: true`.
- The widgets never start, stop or dispose of the queue. Keep the queue somewhere that outlives
  rebuilds, like a `State`, and call `dispose()` on it when you're done.
- Any number of widgets can listen to the same queue, such as a list and a counter in the app bar.
- If a rebuild passes a different queue, the widgets switch to it. Until the new queue changes,
  `builder` still gets the old queue's last snapshot. Updates from the old queue that were still
  waiting for the end of the frame don't reach `listener`.

### Migrating from 0.10

- queue_it 1.0.0 makes an item's `status`, `error` and `stackTrace` read-only, and removes the
  names it deprecated in 0.10.0. Check out the migration notes in its
  [README](https://pub.dev/packages/queue_it).

### Migrating from 0.9

- flutter_queue_it now exports queue_it, so you can remove the `package:queue_it/queue_it.dart`
  import (the analyzer reports it as unnecessary) and the `queue_it` dependency. If you keep the
  dependency, give it the same version as flutter_queue_it.
- queue_it 0.10.0 has a few breaking changes of its own. Check out the migration notes in its
  [README](https://pub.dev/packages/queue_it).
- flutter_queue_it now requires Dart 3.5 and Flutter 3.24 or later.

For a more in-depth example, check out the
[example project](https://pub.dev/packages/flutter_queue_it/example).
