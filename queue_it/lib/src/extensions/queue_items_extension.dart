import 'package:queue_it/src/models/queue_item.dart';
import 'package:queue_it/src/models/queue_item_status.dart';

/// Filters and progress for a collection of queue items, such as
/// `queue.items()` or a snapshot's `items`.
extension QueueItemsExtension<T> on Iterable<QueueItem<T>> {
  /// The items waiting to be processed.
  Iterable<QueueItem<T>> get pending => where(
        (item) => item.status == QueueItemStatus.pending,
      );

  /// The items being processed.
  Iterable<QueueItem<T>> get processing => where(
        (item) => item.status == QueueItemStatus.processing,
      );

  /// The items processed successfully.
  Iterable<QueueItem<T>> get completed => where(
        (item) => item.status == QueueItemStatus.completed,
      );

  /// The items that failed with no retries left. During the `failed` update
  /// of an attempt that will be retried, that item is here too.
  Iterable<QueueItem<T>> get failed => where(
        (item) => item.status == QueueItemStatus.failed,
      );

  /// The canceled items.
  Iterable<QueueItem<T>> get canceled => where(
        (item) => item.status == QueueItemStatus.canceled,
      );

  /// The canceled items.
  @Deprecated('Use canceled')
  Iterable<QueueItem<T>> get cancelled => canceled;

  /// The share of the items that have finished, from 0 to 1, rounded to two
  /// decimal places. Items that are pending or processing haven't finished.
  /// It's 1 when there are no items.
  double get progress {
    if (isEmpty) return 1;
    final inProgressTotal = processing.length + pending.length;
    if (inProgressTotal == 0) return 1;
    final percentage = 1 - (inProgressTotal / length);
    // round to 2 decimal places;
    return double.parse(percentage.toStringAsFixed(2));
  }

  /// A few lines counting the items in each status, and the progress.
  String get summary {
    final s = StringBuffer();
    s.writeln('Total: $length');
    s.writeln('Pending: ${pending.length}');
    s.writeln('Processing: ${processing.length}');
    s.writeln('Completed: ${completed.length}');
    s.writeln('Failed: ${failed.length}');
    s.writeln('Cancelled: ${canceled.length}');
    s.writeln('Progress: ${(progress * 100).round()}%');
    return s.toString();
  }
}
