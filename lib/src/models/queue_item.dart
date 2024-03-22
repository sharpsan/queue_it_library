import 'package:easy_queue/src/models/queue_item_status.dart';

//TODO: should this be an immutable object?  Will that improve performance?
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
    this.clearedAt,
    this.retryCount = 0,
  });

  final T data;
  final String batchId;

  DateTime? queuedAt;
  DateTime? startedProcessingAt;
  DateTime? completedAt;
  DateTime? failedAt;
  DateTime? canceledAt;
  DateTime? clearedAt;
  QueueItemStatus status;
  int retryCount;

  QueueItem<T> copyWith({
    T? data,
    String? batchId,
    DateTime? queuedAt,
    DateTime? startedProcessingAt,
    DateTime? completedAt,
    DateTime? failedAt,
    DateTime? canceledAt,
    DateTime? clearedAt,
    QueueItemStatus? status,
    int? retryCount,
  }) {
    return QueueItem<T>(
      data: data ?? this.data,
      batchId: batchId ?? this.batchId,
      queuedAt: queuedAt ?? this.queuedAt,
      startedProcessingAt: startedProcessingAt ?? this.startedProcessingAt,
      completedAt: completedAt ?? this.completedAt,
      failedAt: failedAt ?? this.failedAt,
      canceledAt: canceledAt ?? this.canceledAt,
      clearedAt: clearedAt ?? this.clearedAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}
