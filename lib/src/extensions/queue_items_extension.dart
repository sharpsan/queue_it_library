import 'package:easy_queue/src/models/queue_item.dart';
import 'package:easy_queue/src/models/queue_item_status.dart';

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
    if (isEmpty || pending.isEmpty) return 1;
    final percentage = 1 - (pending.length / length);
    // round to 2 decimal places;
    return double.parse(percentage.toStringAsFixed(2));
  }
}

class Test<T> {
  final List<QueueItem<T>> _queuedImages = [];

  Iterable<QueueItem<T>> get h => _queuedImages.pending;

  Iterable<QueueItem<T>> grab() => _queuedImages;

  void t() {
    grab().pending;
  }
}