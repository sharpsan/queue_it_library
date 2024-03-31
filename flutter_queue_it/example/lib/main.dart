import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:queue_it/queue_it.dart';
import 'package:faker/faker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_queue_it/flutter_queue_it.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _queue = QueueIt<String>(
    parallel: 3,
    retries: 3,
    useFriendlyIds: true,
    itemHandler: (item) async {
      log('Processing item: $item');

      /// generate a duration between 0.5 and 2 seconds
      final duration = Duration(
        milliseconds: (500 + (math.Random().nextInt(1500))).toInt(),
      );

      await Future.delayed(duration);
    },
  );
  final _faker = Faker();
  StreamSubscription<QueueSnapshot<String>>? _subscription;

  @override
  void initState() {
    _subscription = _queue.onUpdate.listen((snapshot) {
      String message;
      if (snapshot.eventItem != null) {
        message = snapshot.eventItem!.summaryTableLine;
      } else {
        message = snapshot.event.name;
      }
      log(message, name: 'QueueIt');
    });
    super.initState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: QueueItWidget(
        queue: _queue,
        builder: (context, snapshot) {
          final items = _queue.items();
          return Scaffold(
            appBar: AppBar(
              title: const Text('queue_it'),
            ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerDocked,
            floatingActionButton: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  /// Start queue
                  if (_queue.isStarted)
                    FloatingActionButton(
                      onPressed: () {
                        _queue.stop();
                      },
                      tooltip: 'Cancel Queue',
                      backgroundColor: Colors.red,
                      child: const Icon(Icons.stop),
                    )

                  /// "Done" fab
                  else if (_queue.items().pending.isEmpty &&
                      _queue.items().isNotEmpty)
                    FloatingActionButton(
                      backgroundColor: Colors.green,
                      onPressed: () {
                        _queue.removeAll();
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
            body: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                /// Progress bar
                if (_queue.items().processing.isNotEmpty)
                  LinearProgressIndicator(
                    value: _queue.items().progress,
                  ),

                /// Queue list
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('No items in queue'))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items.toList()[index];
                            return Dismissible(
                              key: Key(item.data),
                              onDismissed: (direction) {
                                _queue.remove(item);
                              },
                              child: ListTile(
                                leading: Image.network(item.data),
                                title: Text(item.data),
                                subtitle: Wrap(
                                  children: [
                                    if (item.queuedAt != null)
                                      Text('Added: ${item.queuedAt}'),
                                    if (item.startedProcessingAt != null)
                                      Text(
                                          'Started: ${item.startedProcessingAt}'),
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
              ],
            ),
          );
        },
      ),
    );
  }

  void _addImage(String imageUrl) {
    _queue.add(imageUrl);
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

      /// unused
      case QueueItemStatus.removed:
        return const Icon(Icons.delete);
    }
  }
}
