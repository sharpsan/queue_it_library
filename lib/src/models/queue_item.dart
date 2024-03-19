import 'package:easy_queue/src/models/queue_item_status.dart';

class QueueItem<T> {
  QueueItem({
    required this.data,
    required this.status,
    required this.batchId,
    this.queuedAt,
    this.startedProcessingAt,
    this.completedAt,
    this.failedAt,
    this.canceledAt,
    this.retryCount = 0,
  });

  final T data;
  final String batchId;

  DateTime? queuedAt;
  DateTime? startedProcessingAt;
  DateTime? completedAt;
  DateTime? failedAt;
  DateTime? canceledAt;
  QueueItemStatus status;
  int retryCount;
}
