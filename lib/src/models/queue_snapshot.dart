import 'package:easy_queue/src/models/queue_event.dart';
import 'package:easy_queue/src/models/queue_item.dart';

class QueueSnapshot<T> {
  /// The event that triggered the snapshot.
  final QueueEvent event;

  /// Whether the queue has been started.
  final bool isStarted;

  /// Whether the queue is currently processing items.
  final bool isProcessing;

  /// The current batch id.
  final String currentBatchId;

  /// The item that was updated.
  final QueueItem<T>? updatedItem;

  /// The items in the queue.
  final List<QueueItem<T>> items;

  const QueueSnapshot({
    required this.event,
    required this.isStarted,
    required this.isProcessing,
    required this.currentBatchId,
    required this.updatedItem,
    required this.items,
  });
}
