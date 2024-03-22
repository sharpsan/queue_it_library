import 'package:easy_queue/src/models/queue_event.dart';
import 'package:easy_queue/src/models/queue_item.dart';

class QueueSnapshot<T> {
  final QueueEvent event;
  final bool isRunning;
  final String currentBatchId;
  final QueueItem<T>? updatedItem;
  final List<QueueItem<T>> items;

  QueueSnapshot({
    required this.event,
    required this.isRunning,
    required this.currentBatchId,
    required this.updatedItem,
    required this.items,
  });
}
