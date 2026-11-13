import 'package:queue_it/src/models/queue_item.dart';
import 'package:queue_it/src/models/queue_item_status.dart';

/// Filters and progress for a collection of queue items, such as
/// `queue.items()` or a snapshot's `items`.
///
/// For the queue's own views of its items (`queue.items()`, the current
/// batch and a snapshot's live `items`), the counts come from the queue, so
/// `items.completed.length`, [progress] and [summary] take the same time
/// however many items there are. For other collections, such as a list or an
/// earlier batch, they go through the items.
extension QueueItemsExtension<T> on Iterable<QueueItem<T>> {
  /// The items waiting to be processed.
  Iterable<QueueItem<T>> get pending =>
      _ItemsWithStatus(this, QueueItemStatus.pending);

  /// The items being processed.
  Iterable<QueueItem<T>> get processing =>
      _ItemsWithStatus(this, QueueItemStatus.processing);

  /// The items processed successfully.
  Iterable<QueueItem<T>> get completed =>
      _ItemsWithStatus(this, QueueItemStatus.completed);

  /// The items that failed with no retries left. During the `failed` update
  /// of an attempt that will be retried, that item is here too.
  Iterable<QueueItem<T>> get failed =>
      _ItemsWithStatus(this, QueueItemStatus.failed);

  /// The canceled items.
  Iterable<QueueItem<T>> get canceled =>
      _ItemsWithStatus(this, QueueItemStatus.canceled);

  /// The share of the items that have finished, from 0 to 1, rounded to two
  /// decimal places. Items that are pending or processing haven't finished.
  /// It's 1 only when every item has finished, or when there are no items.
  /// During the `failed` update of an attempt that will be retried, that item
  /// counts as finished.
  double get progress {
    if (isEmpty) return 1;
    final inProgressTotal = processing.length + pending.length;
    if (inProgressTotal == 0) return 1;
    final percentage = 1 - (inProgressTotal / length);
    // Round to 2 decimal places, short of 1 while items are left.
    final rounded = double.parse(percentage.toStringAsFixed(2));
    return rounded < 1 ? rounded : 0.99;
  }

  /// A few lines counting the items and the pending, processing, completed,
  /// failed and canceled ones, and the progress.
  String get summary {
    final s = StringBuffer();
    s.writeln('Total: $length');
    s.writeln('Pending: ${pending.length}');
    s.writeln('Processing: ${processing.length}');
    s.writeln('Completed: ${completed.length}');
    s.writeln('Failed: ${failed.length}');
    s.writeln('Canceled: ${canceled.length}');
    s.writeln('Progress: ${(progress * 100).round()}%');
    return s.toString();
  }
}

/// The items of a collection that have a status: a lazy view, which asks the
/// collection for the count if it knows.
class _ItemsWithStatus<T> extends Iterable<QueueItem<T>> {
  _ItemsWithStatus(this._items, this._status);

  final Iterable<QueueItem<T>> _items;
  final QueueItemStatus _status;

  int? get _count => switch (_items) {
        final CountedItems items => items.countWithStatus(_status),
        _ => null,
      };

  @override
  Iterator<QueueItem<T>> get iterator =>
      _items.where((item) => item.status == _status).iterator;

  @override
  int get length => _count ?? super.length;

  @override
  bool get isEmpty => switch (_count) {
        final count? => count == 0,
        null => super.isEmpty,
      };

  @override
  bool get isNotEmpty => !isEmpty;
}
