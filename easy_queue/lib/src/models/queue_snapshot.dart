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

  /// The subject item of the event, if any.
  final QueueItem<T>? eventItem;

  /// The items in the queue at the time of the snapshot.
  final List<QueueItem<T>> items;

  const QueueSnapshot({
    required this.event,
    required this.isStarted,
    required this.isProcessing,
    required this.currentBatchId,
    required this.eventItem,
    required this.items,
  });
}
