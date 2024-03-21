import 'package:easy_queue/easy_queue.dart';
import 'package:faker/faker.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _queue = EasyQueue<String>();
  final _faker = Faker();

  @override
  void initState() {
    _queue
      ..itemHandler = (item) async {
        print('Processing item: $item');
        await Future.delayed(const Duration(seconds: 1));
      }
      ..onStart.listen((event) {
        print('Upload started: $event');
      })
      ..onUpdate.listen((event) {
        print('Upload updated: $event');
      })
      ..onDone.listen((event) {
        print('Upload done: $event');
      });
    super.initState();
  }

  void _addImage(String imageUrl) {
    _queue.add(imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final items = _queue.items();
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('easy_queue'),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              /// Start queue
              if (_queue.isProcessing)
                FloatingActionButton(
                  onPressed: () {
                    _queue.stop();
                  },
                  tooltip: 'Cancel Queue',
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.stop),
                )

              /// "Done" fab
              else if (_queue.items().pending.isEmpty)
                FloatingActionButton(
                  backgroundColor: Colors.green,
                  onPressed: () {
                    _queue.clearAll();
                  },
                  child: const Icon(Icons.check),
                )

              /// Start queue
              else
                FloatingActionButton(
                  onPressed: () {
                    _queue.start();
                  },
                  tooltip: 'Start Queue',
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.play_arrow),
                ),

              /// Add image button
              FloatingActionButton(
                onPressed: () {
                  _addImage(
                    _faker.image.image(
                      random: true,
                    ),
                  );
                },
                tooltip: 'Add Image',
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        body: items.isEmpty
            ? const Center(child: Text('No items in queue'))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items.toList()[index];
                  return Dismissible(
                    key: Key(item.data),
                    onDismissed: (direction) {
                      _queue.clear(item);
                    },
                    child: ListTile(
                      leading: Image.network(item.data),
                      title: Text(item.data),
                      subtitle: Wrap(
                        children: [
                          if (item.queuedAt != null)
                            Text('Added: ${item.queuedAt}'),
                          if (item.startedProcessingAt != null)
                            Text('Started: ${item.startedProcessingAt}'),
                          if (item.completedAt != null)
                            Text('Done: ${item.completedAt}'),
                          if (item.failedAt != null)
                            Text('Failed: ${item.failedAt}'),
                        ],
                      ),
                      trailing: _iconFromStatus(item.status),
                    ),
                  );
                },
              ),
      ),
    );
  }

  /// Returns an icon based on the status of the item
  Icon _iconFromStatus(QueueItemStatus status) {
    switch (status) {
      case QueueItemStatus.pending:
        return const Icon(Icons.timer);
      case QueueItemStatus.processing:
        return const Icon(Icons.hourglass_top);
      case QueueItemStatus.completed:
        return const Icon(Icons.check);
      case QueueItemStatus.failed:
        return const Icon(Icons.error);
      case QueueItemStatus.canceled:
        return const Icon(Icons.cancel);
    }
  }
}
