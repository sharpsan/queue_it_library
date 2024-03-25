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

# EasyQueue

![Pub Version](https://img.shields.io/pub/v/easy_queue?label=easy_queue)
![Pub Version](https://img.shields.io/pub/v/flutter_easy_queue?label=flutter_easy_queue)
[![codecov](https://codecov.io/gh/sharpsan/easy_queue_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/easy_queue_library)

EasyQueue is designed to simplify the process of managing and processing queues in your Flutter and Dart
applications.

## Features

- Queue management: Easily add, remove, and process items in a queue.
- Event listeners: Listen for updates to the queue and receive snapshots.
- Concurrency: Control the number of items processed simultaneously.
- Retries: Automatically retry failed items.

## Installation

To use this library in your project, add it to your `pubspec.yaml` file:

```yaml
dependencies:
  easy_queue: ^0.0.1
```

Then, run `flutter pub get` to fetch the package.

## Usage

Here's a basic example of how to use Easy Queue:

```dart
import 'package:easy_queue/easy_queue.dart';

void main() {
  final queue = EasyQueue<int>(
      concurrentOperations: 1,
      retryLimit: 3,
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

For a more in-depth look at how to use EasyQueue, check out the example project.

## Documentation

For more information on how to use EasyQueue, including a full API reference, check out
the [documentation](https://example.com/docs).

## Contributing

We welcome contributions! Please see our [contributing guide](https://example.com/contributing) for more
information.

## License

EasyQueue is licensed under the [MIT License](https://example.com/license).
