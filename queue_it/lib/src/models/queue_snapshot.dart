import 'package:queue_it/src/models/queue_event.dart';
import 'package:queue_it/src/models/queue_item.dart';

/// The state of a queue when an event happened, sent on the queue's
/// `onUpdate` stream.
///
/// The queue's flags and times are as they were at the event, and
/// [eventItem] is a copy of the item involved, taken at that moment.
/// [items] is different: unless the queue copies items into snapshots, it
/// holds the queue's live items, which keep changing.
class QueueSnapshot<T> {
  /// The event that triggered the snapshot.
  final QueueEvent event;

  /// The number of times the queue retries a failed item.
  final int retries;

  /// Whether the queue had been started.
  final bool isStarted;

  /// Whether the queue was processing items.
  final bool isProcessing;

  /// The queue's current batch id.
  final String currentBatchId;

  /// A copy of the item the event is about, taken at the time of the event,
  /// or null for events about the whole queue.
  final QueueItem<T>? eventItem;

  /// Whether the queue is about to retry [eventItem]: true in the `failed`
  /// update of an attempt that will be retried, unless a listener cancels or
  /// removes the item. When an item's `failed` update has it false, the item
  /// has failed for good.
  final bool willRetry;

  /// The items in the queue's current batch.
  ///
  /// Unless the queue was created with `deepCopyItemsInSnapshot: true`, this
  /// is a live view of the queue's items: iterating it later shows the items
  /// as they are then, and adding or removing items while iterating it
  /// throws a [ConcurrentModificationError]. Copy it with `toList()` to keep
  /// it. The live view counts its items without going through them.
  final Iterable<QueueItem<T>> items;

  /// When the queue was last started.
  final DateTime? startedAt;

  /// When the queue last started processing items.
  final DateTime? startedProcessingAt;

  /// When the queue last stopped processing items.
  final DateTime? stoppedProcessingAt;

  /// When the queue was last stopped.
  final DateTime? stoppedAt;

  @override
  String toString() {
    final s = StringBuffer();
    s.writeln('Event: ${event.name}');
    s.writeln('Retries: $retries');
    s.writeln('Started: $isStarted');
    s.writeln('Processing: $isProcessing');
    s.writeln('Current Batch Id: $currentBatchId');
    s.writeln('Event Item: ${eventItem?.data}');
    s.writeln('Will Retry: $willRetry');
    s.writeln('Items: ${items.map((e) => e.data).toList()}');
    s.writeln('Started At: $startedAt');
    s.writeln('Started Processing At: $startedProcessingAt');
    s.writeln('Stopped Processing At: $stoppedProcessingAt');
    s.writeln('Stopped At: $stoppedAt');
    return s.toString();
  }

  /// Creates a snapshot. Queues create them; you don't need to.
  const QueueSnapshot({
    required this.event,
    required this.retries,
    required this.isStarted,
    required this.isProcessing,
    required this.currentBatchId,
    required this.eventItem,
    this.willRetry = false,
    required this.items,
    required this.startedAt,
    required this.startedProcessingAt,
    required this.stoppedProcessingAt,
    required this.stoppedAt,
  });
}
