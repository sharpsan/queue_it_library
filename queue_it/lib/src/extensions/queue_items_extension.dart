import 'package:queue_it/src/models/queue_item.dart';
import 'package:queue_it/src/models/queue_item_status.dart';

extension QueueItemsExtension<T> on Iterable<QueueItem<T>> {
  Iterable<QueueItem<T>> get pending => where(
        (item) => item.status == QueueItemStatus.pending,
      );
  Iterable<QueueItem<T>> get processing => where(
        (item) => item.status == QueueItemStatus.processing,
      );
  Iterable<QueueItem<T>> get completed => where(
        (item) => item.status == QueueItemStatus.completed,
      );
  Iterable<QueueItem<T>> get failed => where(
        (item) => item.status == QueueItemStatus.failed,
      );
  Iterable<QueueItem<T>> get cancelled => where(
        (item) => item.status == QueueItemStatus.canceled,
      );

  /// progress
  double get progress {
    if (isEmpty) return 1;
    final inProgressTotal = processing.length + pending.length;
    if (inProgressTotal == 0) return 1;
    final percentage = 1 - (inProgressTotal / length);
    // round to 2 decimal places;
    return double.parse(percentage.toStringAsFixed(2));
  }

  String get summary {
    final s = StringBuffer();
    s.writeln('Total: $length');
    s.writeln('Pending: ${pending.length}');
    s.writeln('Processing: ${processing.length}');
    s.writeln('Completed: ${completed.length}');
    s.writeln('Failed: ${failed.length}');
    s.writeln('Cancelled: ${cancelled.length}');
    s.writeln('Progress: ${progress * 100}%');
    return s.toString();
  }
}
