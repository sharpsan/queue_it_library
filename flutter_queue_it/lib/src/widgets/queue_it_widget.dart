import 'package:queue_it/queue_it.dart';
import 'package:flutter/widgets.dart';

/// A widget that rebuilds whenever a [QueueIt] changes.
///
/// [QueueItWidget] listens to the queue's [QueueIt.onUpdate] stream and calls
/// [builder] with the latest [QueueSnapshot]:
///
/// ```dart
/// QueueItWidget<String>(
///   queue: queue,
///   builder: (context, snapshot) {
///     final items = queue.items().toList();
///     return ListView.builder(
///       itemCount: items.length,
///       itemBuilder: (context, index) => ListTile(
///         title: Text(items[index].data),
///         trailing: Text(items[index].status.name),
///       ),
///     );
///   },
/// )
/// ```
///
/// ## When the builder runs
///
/// The first build happens before the queue has sent the widget any event,
/// so `snapshot` is null. The queue doesn't replay events sent before the
/// widget started listening, so a queue that already has items still gives a
/// null snapshot until its next change.
///
/// After that, each queue event schedules a rebuild. Events that arrive in the
/// same frame cause a single rebuild with the latest snapshot, so the builder
/// doesn't see every event. To act on each event, such as to log it, listen
/// to [QueueIt.onUpdate] yourself.
///
/// ## The queue or the snapshot
///
/// To show the queue's current state, read it from the queue, for example
/// with [QueueIt.items], [QueueIt.isStarted] and [QueueIt.isProcessing]. That
/// works on the first build too.
///
/// The snapshot describes the event behind the rebuild:
/// [QueueSnapshot.event] says what happened, and [QueueSnapshot.eventItem] is
/// a copy of the item involved, taken at that moment. [QueueSnapshot.items]
/// holds the items of the queue's current batch. Unless the queue was created
/// with [QueueIt.deepCopyItemsInSnapshot] set, those are the queue's live
/// items, so they show each item's current status, not its status at the time
/// of the event.
///
/// ## Owning the queue
///
/// The widget never starts, stops or disposes the queue. Create the queue in a
/// [State] and call [QueueIt.dispose] from [State.dispose]. Several
/// [QueueItWidget]s can listen to the same queue.
class QueueItWidget<T> extends StatefulWidget {
  /// Creates a widget that calls [builder] whenever [queue] changes.
  const QueueItWidget({
    super.key,
    required this.queue,
    required this.builder,
  });

  /// The queue to listen to.
  ///
  /// If a rebuild passes a different queue, the widget listens to the new one
  /// instead. Until the new queue sends an event, [builder] still receives the
  /// previous queue's last snapshot.
  final QueueIt<T> queue;

  /// Builds the widget from the latest snapshot of [queue].
  ///
  /// `snapshot` is null until the queue sends its first event after the widget
  /// starts listening.
  final Widget Function(
    BuildContext context,
    QueueSnapshot<T>? snapshot,
  ) builder;

  @override
  State<QueueItWidget<T>> createState() => _QueueItWidgetState<T>();
}

class _QueueItWidgetState<T> extends State<QueueItWidget<T>> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueueSnapshot<T>>(
      stream: widget.queue.onUpdate,
      builder: (
        BuildContext context,
        AsyncSnapshot<QueueSnapshot<T>> snapshot,
      ) {
        return widget.builder(context, snapshot.data);
      },
    );
  }
}
