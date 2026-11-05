import 'dart:async';

import 'package:queue_it/queue_it.dart';
import 'package:flutter/widgets.dart';

/// A widget that calls [listener] for every event of a [QueueIt], without
/// rebuilding.
///
/// Use it for things to do once per event, such as showing a message,
/// logging or navigating. Unlike a [QueueItWidget]'s builder, [listener] gets
/// every event, in order, as the queue sends it:
///
/// ```dart
/// QueueItListener<String>(
///   queue: queue,
///   listener: (context, snapshot) {
///     final item = snapshot.eventItem;
///     if (item != null && item.status == QueueItemStatus.failed) {
///       ScaffoldMessenger.of(context).showSnackBar(
///         SnackBar(content: Text('${item.data} failed')),
///       );
///     }
///   },
///   child: const UploadList(),
/// )
/// ```
///
/// The listener runs synchronously, inside the queue call that caused the
/// event. It can call the queue. The widget never starts, stops or disposes
/// the queue.
class QueueItListener<T> extends StatefulWidget {
  /// Creates a widget that calls [listener] for every event of [queue].
  const QueueItListener({
    super.key,
    required this.queue,
    required this.listener,
    required this.child,
  });

  /// The queue to listen to.
  ///
  /// If a rebuild passes a different queue, the widget listens to the new one
  /// instead.
  final QueueIt<T> queue;

  /// Called with each event's snapshot.
  final void Function(BuildContext context, QueueSnapshot<T> snapshot) listener;

  /// The widget below this one.
  final Widget child;

  @override
  State<QueueItListener<T>> createState() => _QueueItListenerState<T>();
}

class _QueueItListenerState<T> extends State<QueueItListener<T>> {
  StreamSubscription<QueueSnapshot<T>>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(QueueItListener<T> oldWidget) {
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
      if (mounted) widget.listener(context, snapshot);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
