# flutter_queue_it


![Pub Version](https://img.shields.io/pub/v/flutter_queue_it?label=flutter_queue_it)
[![codecov](https://codecov.io/gh/sharpsan/queue_it_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/queue_it_library)

> Flutter integration with [queue_it](https://pub.dev/packages/queue_it).

Provides the **`QueueItWidget`** widget that listens to the queue and automatically
rebuilds on changes.

### Example

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

For a more in-depth example, check out the example project.
