import 'package:easy_queue/src/models/queue_item_status.dart';
import 'package:uuid/uuid.dart';

//TODO: should this be an immutable object?  Will that improve performance?
class QueueItem<T> {
  QueueItem({
    required this.data,
    required QueueItemStatus status,
    required this.batchId,
    String? id,
    this.retryCount = 0,
  }) : id = id ?? const Uuid().v4();

  final String id;

  final T data;
  final String batchId;

  DateTime? _queuedAt;
  DateTime? _startedProcessingAt;
  DateTime? _completedAt;
  DateTime? _failedAt;
  DateTime? _canceledAt;
  DateTime? _removedAt;

  QueueItemStatus _status = QueueItemStatus.pending;

  QueueItemStatus get status => _status;

  DateTime? get queuedAt => _queuedAt;

  DateTime? get startedProcessingAt => _startedProcessingAt;

  DateTime? get completedAt => _completedAt;

  DateTime? get failedAt => _failedAt;

  DateTime? get canceledAt => _canceledAt;

  DateTime? get removedAt => _removedAt;

  set status(QueueItemStatus value) {
    if (value == _status) return;
    final now = DateTime.now();
    switch (value) {
      case QueueItemStatus.processing:
        _startedProcessingAt = now;
      case QueueItemStatus.completed:
        _completedAt = now;
      case QueueItemStatus.failed:
        _failedAt = now;
      case QueueItemStatus.canceled:
        _canceledAt = now;
      case QueueItemStatus.removed:
        _removedAt = now;
      case QueueItemStatus.pending:
        _queuedAt = now;
    }
    _status = value;
  }

  int retryCount;

  QueueItem<T> copyWith({
    String? id,
    T? data,
    String? batchId,
    DateTime? queuedAt,
    DateTime? startedProcessingAt,
    DateTime? completedAt,
    DateTime? failedAt,
    DateTime? canceledAt,
    DateTime? removedAt,
    QueueItemStatus? status,
    int? retryCount,
  }) {
    return QueueItem<T>(
      id: id ?? this.id,
      data: data ?? this.data,
      batchId: batchId ?? this.batchId,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
    )
      .._queuedAt = queuedAt ?? this.queuedAt
      .._startedProcessingAt = startedProcessingAt ?? this.startedProcessingAt
      .._completedAt = completedAt ?? this.completedAt
      .._failedAt = failedAt ?? this.failedAt
      .._canceledAt = canceledAt ?? this.canceledAt
      .._removedAt = removedAt ?? this.removedAt;
  }
}
