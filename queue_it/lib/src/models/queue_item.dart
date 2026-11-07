import 'package:queue_it/src/models/queue_item_status.dart';
import 'package:uuid/uuid.dart';

/// An item in a queue: its data, its status and when the status changed.
///
/// The queue creates items when you add data to it and passes them to its
/// item handler. The queue's own items are live: their status changes as the
/// queue processes them. Only the queue changes them: to cancel or remove an
/// item, use the queue's methods, and to choose what happens to an item when
/// its handler returns, set [nextStatus]. A snapshot's `eventItem` is a copy,
/// made with [copyWith], and so are its `items` if the queue copies them.
class QueueItem<T> {
  /// Creates an item with [status]. Without an [id], it gets a random UUID.
  QueueItem({
    required this.data,
    required QueueItemStatus status,
    required this.batchId,
    String? id,
  }) : id = id ?? const Uuid().v4() {
    _setStatus(status);
  }

  /// The unique id of the item.
  final String id;

  /// The data that the item represents.
  final T data;

  /// The id of the batch that the item belongs to.
  ///
  /// Items added while the queue has unfinished items join its current batch.
  /// Once every item has finished, the next item added starts a new batch.
  final String batchId;

  /// How many times the item has gone back to [QueueItemStatus.pending] to
  /// be processed again, whether to retry a failure or because its handler
  /// set [nextStatus] to pending.
  int get retryCount => _retryCount ?? 0;

  /// The current status of the item.
  QueueItemStatus get status => _status!;

  /// The status the item moves to when its handler returns, if the handler
  /// sets it.
  ///
  /// Without it, an item whose handler returns is
  /// [QueueItemStatus.completed], and one whose handler throws has failed.
  /// The handler can instead set:
  ///
  /// - [QueueItemStatus.failed] to fail the attempt without throwing. Retries
  ///   apply, and [error] is null.
  /// - [QueueItemStatus.canceled] or [QueueItemStatus.removed] to cancel or
  ///   remove the item.
  /// - [QueueItemStatus.pending] to process the item again, after the items
  ///   already waiting. This isn't limited by the queue's retries, but it adds
  ///   to [retryCount], which leaves fewer retries for failures. The next
  ///   attempt can come before timers and I/O get to run, so to wait for
  ///   something, await it (for example a `Future.delayed`) before
  ///   returning.
  ///
  /// [QueueItemStatus.processing] isn't allowed: the attempt fails with a
  /// [StateError].
  ///
  /// If the handler throws, the attempt fails, whatever it set. The queue
  /// clears it as the handler starts, so a value set before then doesn't
  /// count, and again once it has applied the attempt's outcome.
  QueueItemStatus? nextStatus;

  /// The error that made the item's last failed attempt fail, or null if no
  /// attempt has failed or the handler failed it through [nextStatus].
  ///
  /// The queue keeps it when a later attempt succeeds.
  Object? get error => _error;

  /// The stack trace of [error].
  StackTrace? get stackTrace => _stackTrace;

  /// When the item last became [QueueItemStatus.pending]: when it was added,
  /// or when it was queued again.
  DateTime? get queuedAt => _queuedAt;

  /// When the item's last attempt started.
  DateTime? get startedProcessingAt => _startedProcessingAt;

  /// When the item was completed.
  DateTime? get completedAt => _completedAt;

  /// When the item's last attempt failed.
  DateTime? get failedAt => _failedAt;

  /// When the item was canceled.
  DateTime? get canceledAt => _canceledAt;

  /// When the item was removed from the queue.
  DateTime? get removedAt => _removedAt;

  QueueItemStatus? _status;

  int? _retryCount;

  Object? _error;
  StackTrace? _stackTrace;

  DateTime? _queuedAt;
  DateTime? _startedProcessingAt;
  DateTime? _completedAt;
  DateTime? _failedAt;
  DateTime? _canceledAt;
  DateTime? _removedAt;

  /// Changes the status and records when it changed.
  void _setStatus(QueueItemStatus value) {
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
    if (error != null) s.writeln('Error: $error');
    return s.toString();
  }

  /// A one-line summary of the item's status, data and id, for logging.
  String get summaryTableLine {
    final s = StringBuffer();
    s.write(status.name.padRight(15));
    s.write(' | ');
    s.write(data.toString().padRight(22));
    s.write(' | ');
    s.write(id.toString().padRight(22));

    return s.toString();
  }

  /// Returns a copy of the item, with the given fields replaced.
  ///
  /// The other fields keep the item's values: a new [status] doesn't change
  /// when the item reached each status, and [nextStatus] isn't copied.
  /// The copy is a separate object: it doesn't change as the original does.
  /// Queue methods that take an item find the queue's item by its [id], so
  /// they work with copies too.
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
    Object? error,
    StackTrace? stackTrace,
  }) {
    return QueueItem<T>(
      id: id ?? this.id,
      data: data ?? this.data,
      batchId: batchId ?? this.batchId,
      status: status ?? this.status,
    )
      .._retryCount = retryCount ?? this.retryCount
      .._queuedAt = queuedAt ?? this.queuedAt
      .._startedProcessingAt = startedProcessingAt ?? this.startedProcessingAt
      .._completedAt = completedAt ?? this.completedAt
      .._failedAt = failedAt ?? this.failedAt
      .._canceledAt = canceledAt ?? this.canceledAt
      .._removedAt = removedAt ?? this.removedAt
      .._error = error ?? this.error
      .._stackTrace = stackTrace ?? this.stackTrace;
  }
}

/// How the queue changes its items. The public library hides it, so only the
/// queue changes an item.
extension QueueItemUpdates<T> on QueueItem<T> {
  /// Changes the status and records when it changed.
  void updateStatus(QueueItemStatus status) => _setStatus(status);

  /// Records why the item's last attempt failed.
  void recordError(Object? error, StackTrace? stackTrace) {
    _error = error;
    _stackTrace = stackTrace;
  }
}
