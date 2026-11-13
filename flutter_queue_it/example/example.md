# flutter_queue_it example

This app processes "uploads" two at a time and lists them with their status:

```dart
// lib/main.dart
import 'package:flutter_queue_it/flutter_queue_it.dart';
import 'package:material_ui/material_ui.dart';

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

It gets its Material widgets from the [material_ui](https://pub.dev/packages/material_ui) package,
which needs Flutter 3.47 or later. On older versions, skip it and import
`package:flutter/material.dart` instead.

For a bigger example, check out the
[photo uploader](https://github.com/sharpsan/queue_it_library/tree/main/flutter_queue_it/example):
three uploads at a time, with progress, retries, cancel and pause.
