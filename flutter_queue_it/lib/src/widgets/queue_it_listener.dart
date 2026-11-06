import 'dart:async';

import 'package:queue_it/queue_it.dart';
import 'package:flutter/scheduler.dart';
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
///     if (item != null && item.status == QueueItemStatus.completed) {
///       ScaffoldMessenger.of(context).showSnackBar(
///         SnackBar(content: Text('${item.data} uploaded')),
///       );
///     }
///   },
///   child: const UploadList(),
/// )
/// ```
///
/// The listener runs synchronously, inside the queue call that caused the
/// event. It can call the queue. If that call was made while Flutter builds
/// or disposes widgets, from a widget's `initState` or `dispose` for example,
/// the listener runs then too, so it can't show a SnackBar or change other
/// widgets' state at that moment.
///
/// The listener isn't called once the widget is being removed. When the
/// widget moves to a new place in the tree (with a [GlobalKey]), the events
/// sent during the move reach its listener in order, right after that frame,
/// unless it's given another queue at the same time. The widget never starts,
/// stops or disposes the queue.
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

  /// The events kept since the widget was deactivated, until they're
  /// delivered after the frame it came back in. Null while events go straight
  /// to the listener.
  List<QueueSnapshot<T>>? _deferred;
  var _isDeliveryScheduled = false;

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
      // The events kept during a move came from the old queue.
      _deferred?.clear();
      _listen();
    }
  }

  // A widget being removed or moved is deactivated first, and its context
  // can't be used until it's back in the tree. Events can arrive in between,
  // for example when another widget changes the queue from its initState or
  // dispose. They're kept for a move, and dropped with the widget otherwise.
  @override
  void deactivate() {
    _deferred ??= [];
    super.deactivate();
  }

  // Back in the tree after a move with a GlobalKey. Flutter is building, and
  // the widget may still get its new configuration, so the kept events wait
  // for the end of the frame.
  @override
  void activate() {
    super.activate();
    if (_isDeliveryScheduled) return;
    if (_deferred!.isEmpty) {
      _deferred = null;
      return;
    }
    _isDeliveryScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _deliverDeferred())
      ..ensureVisualUpdate();
  }

  void _deliverDeferred() {
    _isDeliveryScheduled = false;
    final deferred = _deferred;
    if (!mounted || deferred == null) return;
    // Events the listener causes join the list, so they stay in order.
    for (var i = 0; i < deferred.length; i++) {
      try {
        widget.listener(context, deferred[i]);
      } catch (error, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'flutter_queue_it',
          context: ErrorDescription('while calling a QueueItListener'),
        ));
      }
    }
    _deferred = null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _listen() {
    _subscription = widget.queue.onUpdate.listen((snapshot) {
      final deferred = _deferred;
      if (deferred != null) {
        deferred.add(snapshot);
      } else if (mounted) {
        widget.listener(context, snapshot);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
