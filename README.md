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

# Easy Queue

Easy Queue is a Flutter library designed to simplify the process of managing and processing queues in your Flutter applications.

## Features

- Queue management: Easily add, remove, and process items in a queue.
- Event listeners: Listen for updates to the queue and react accordingly.
- Extensions: Extend the functionality of your queues with additional methods.

## Installation

To use this library in your project, add it to your `pubspec.yaml` file:

```yaml
dependencies:
  easy_queue: ^1.0.0
```

Then, run `flutter pub get` to fetch the package.

## Usage

Here's a basic example of how to use Easy Queue:

```dart
import 'package:easy_queue/easy_queue.dart';

void main() {
  final queue = EasyQueue<int>()
    ..itemHandler = (item) async {
    print('Handling item: $item');
    await Future.delayed(Duration(seconds: 1));
  }
  ..onUpdate.listen((event) {
    print('Queue updated: $event');
  });

  queue.add(1);
  queue.add(2);
  queue.add(3);
  
  queue.start();
  
  print(queue.items); // Prints: [1, 2, 3]
}
```

In this example, we create an `EasyQueue` of integers, define an `itemHandler`, add a listener for the `onUpdate` event, and add some items to the queue.

For a more in-depth look at how to use Easy Queue, check out the example project.

## Documentation

For more information on how to use Easy Queue, including a full API reference, check out the [documentation](https://example.com/docs).

## Contributing

We welcome contributions to Easy Queue! Please see our [contributing guide](https://example.com/contributing) for more information.

## License

Easy Queue is licensed under the [MIT License](https://example.com/license).
