import 'package:queue_it/src/models/queue_event.dart';
import 'package:queue_it/src/models/queue_item.dart';

class QueueSnapshot<T> {
  /// The event that triggered the snapshot.
  final QueueEvent event;

  /// The number of times we will retry an item.
  final int retries;

  /// Whether the queue has been started.
  final bool isStarted;

  /// Whether the queue is currently processing items.
  final bool isProcessing;

  /// The current batch id.
  final String currentBatchId;

  /// The subject item of the event, if any.
  final QueueItem<T>? eventItem;

  /// The items in the queue at the time of the snapshot.
  final Iterable<QueueItem<T>> items;

  /// The time the queue was started.
  final DateTime? startedAt;

  /// The time the queue was started processing.
  final DateTime? startedProcessingAt;

  /// The time the queue was stopped processing.
  final DateTime? stoppedProcessingAt;

  /// The time the queue was stopped.
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
    s.writeln('Items: ${items.map((e) => e.data).toList()}');
    s.writeln('Started At: $startedAt');
    s.writeln('Started Processing At: $startedProcessingAt');
    s.writeln('Stopped Processing At: $stoppedProcessingAt');
    s.writeln('Stopped At: $stoppedAt');
    return s.toString();
  }

  const QueueSnapshot({
    required this.event,
    required this.retries,
    required this.isStarted,
    required this.isProcessing,
    required this.currentBatchId,
    required this.eventItem,
    required this.items,
    required this.startedAt,
    required this.startedProcessingAt,
    required this.stoppedProcessingAt,
    required this.stoppedAt,
  });
}
