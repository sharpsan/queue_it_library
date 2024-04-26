<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages).
-->

# QueueIt

[![Pub Version](https://img.shields.io/pub/v/queue_it?label=queue_it)](https://pub.dev/packages/queue_it)
[![codecov](https://codecov.io/gh/sharpsan/queue_it_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/queue_it_library)

QueueIt is designed to simplify the process of managing and processing queues in your Flutter and Dart
applications.

## Features

- Queue management: Easily add, remove, and process items in a queue.
- Event listeners: Listen for updates to the queue and receive snapshots.
- Concurrency: Control the number of items processed simultaneously.
- Retries: Automatically retry failed items.

## Usage

Here's a basic example of how to use QueueIt:

```dart
import 'package:queue_it/queue_it.dart';

void main() {
  final queue = QueueIt<int>(
      parallel: 1,
      retries: 3,
      itemHandler: (item) async {
        print('Handling item: ${item.id}');
        /// Fake processing time
        await Future.delayed(Duration(seconds: 1));
      })
    ..onUpdate.listen((snapshot) {
      print('Queue updated: ${snapshot.event.name}');
    });

  /// Add some items to the queue
  queue.add(1);
  queue.add(2);
  queue.add(3);

  /// start processing the queue
  queue.start();

  /// You can continue adding more items to the queue after it starts processing
  queue.add(4);
  queue.add(5);
}
```

For Flutter projects you will want to use [flutter_queue_it](https://website-name.com), which listens to queue changes and rebuilds your widget tree:
```dart
QueueItWidget(
  queue: _queue,
  builder: (context, snapshot) {
    /// `builder` will be called each time the queue updates
    final items = _queue.items().toList();
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text('Item status: ${item.status.name}'),
        );
      },
    );
  },
);
```

For a more in-depth look at how to use QueueIt, check out the example project.

## License

QueueIt is licensed under the [MIT License](https://github.com/sharpsan/queue_it_library/blob/main/queue_it/LICENSE).
