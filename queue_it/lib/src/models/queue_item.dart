import 'package:queue_it/src/models/queue_item_status.dart';
import 'package:uuid/uuid.dart';

//TODO: should this be an immutable object?  Will that improve performance?
class QueueItem<T> {
  QueueItem({
    required this.data,
    required QueueItemStatus status,
    required this.batchId,
    String? id,
  }) : id = id ?? const Uuid().v4() {
    this.status = status;
  }

  /// The unique id of the item.
  final String id;

  /// The data that the item represents.
  final T data;

  /// The id of the batch that the item belongs to.
  ///
  /// This is used to group items together for processing and
  /// is regenerated each time the queue completes all pending items.
  final String batchId;

  /// The number of times the item has attempted to be processed.
  int get retryCount => _retryCount ?? 0;

  /// The current status of the item.
  QueueItemStatus get status => _status!;

  /// The next status that the item should transition to.
  QueueItemStatus? nextStatus;

  DateTime? get queuedAt => _queuedAt;

  DateTime? get startedProcessingAt => _startedProcessingAt;

  DateTime? get completedAt => _completedAt;

  DateTime? get failedAt => _failedAt;

  DateTime? get canceledAt => _canceledAt;

  DateTime? get removedAt => _removedAt;

  QueueItemStatus? _status;

  int? _retryCount;

  DateTime? _queuedAt;
  DateTime? _startedProcessingAt;
  DateTime? _completedAt;
  DateTime? _failedAt;
  DateTime? _canceledAt;
  DateTime? _removedAt;

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
        if (_retryCount == null) {
          _retryCount = 0;
        } else {
          _retryCount = _retryCount! + 1;
        }
    }
    _status = value;
  }

  @override
  String toString() {
    final s = StringBuffer();
    s.writeln('Id: $id');
    s.writeln('Data: $data');
    s.writeln('Batch Id: $batchId');
    s.writeln('Status: $status');
    s.writeln('Queued At: $queuedAt');
    s.writeln('Started Processing At: $startedProcessingAt');
    s.writeln('Completed At: $completedAt');
    s.writeln('Failed At: $failedAt');
    s.writeln('Canceled At: $canceledAt');
    s.writeln('Removed At: $removedAt');
    return s.toString();
  }

  String get summaryTableLine {
    final s = StringBuffer();
    s.write(status.name.padRight(15));
    s.write(' | ');
    s.write(data.toString().padRight(22));
    s.write(' | ');
    s.write(id.toString().padRight(22));

    return s.toString();
  }

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
    )
      ..status = status ?? this.status
      .._retryCount = retryCount ?? this.retryCount
      .._queuedAt = queuedAt ?? this.queuedAt
      .._startedProcessingAt = startedProcessingAt ?? this.startedProcessingAt
      .._completedAt = completedAt ?? this.completedAt
      .._failedAt = failedAt ?? this.failedAt
      .._canceledAt = canceledAt ?? this.canceledAt
      .._removedAt = removedAt ?? this.removedAt;
  }
}
