import 'dart:async';

import 'package:queue_it/queue_it.dart';
import 'package:flutter/scheduler.dart';
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
/// After that, each queue event schedules a rebuild, unless [buildWhen] skips
/// it. Events that arrive in the same frame cause a single rebuild with the
/// latest snapshot, so the builder doesn't see every event. To act on each
/// event, such as to show a message, use a [QueueItListener].
///
/// Flutter doesn't allow rebuilding while it builds, lays out or disposes
/// widgets, which is when a widget's `initState`, `build` or `dispose` might
/// change the queue. Events sent then rebuild the widget once that frame is
/// done.
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
/// of the event, and items removed since are gone.
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
    this.buildWhen,
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

  /// Decides whether an event rebuilds the widget. Without it, every event
  /// does.
  ///
  /// It's called with the snapshot of each event. When it returns false, the
  /// widget doesn't rebuild, and the snapshot the builder gets stays the last
  /// one that passed. For example, to rebuild only when items are added or
  /// removed:
  ///
  /// ```dart
  /// buildWhen: (snapshot) => const {
  ///   QueueEvent.itemAdded,
  ///   QueueEvent.itemRemoved,
  ///   QueueEvent.removedAll,
  /// }.contains(snapshot.event),
  /// ```
  final bool Function(QueueSnapshot<T> snapshot)? buildWhen;

  @override
  State<QueueItWidget<T>> createState() => _QueueItWidgetState<T>();
}

class _QueueItWidgetState<T> extends State<QueueItWidget<T>> {
  StreamSubscription<QueueSnapshot<T>>? _subscription;
  QueueSnapshot<T>? _snapshot;
  var _isRebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(QueueItWidget<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queue != widget.queue) {
      _subscription?.cancel();
      _listen();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _listen() {
    _subscription = widget.queue.onUpdate.listen((snapshot) {
      if (!(widget.buildWhen?.call(snapshot) ?? true)) return;
      if (!_isBuilding) {
        setState(() => _snapshot = snapshot);
        return;
      }
      // Flutter is building: rebuild once the frame is done.
      _snapshot = snapshot;
      if (_isRebuildScheduled) return;
      _isRebuildScheduled = true;
      SchedulerBinding.instance
        ..addPostFrameCallback((_) {
          _isRebuildScheduled = false;
          if (mounted) setState(() {});
        })
        ..ensureVisualUpdate();
    });
  }

  /// Whether Flutter is building, laying out or disposing widgets: during a
  /// frame, or while it builds the app's first widgets in runApp. In release
  /// mode the only sign of that first build is that the app has no root
  /// element yet. A tree with a BuildOwner of its own isn't the app's.
  bool get _isBuilding =>
      SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks ||
      (WidgetsBinding.instance.rootElement == null &&
          identical(context.owner, WidgetsBinding.instance.buildOwner)) ||
      (WidgetsBinding.instance.buildOwner?.debugBuilding ?? false);

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
}
