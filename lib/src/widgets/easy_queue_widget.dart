import 'dart:async';

import 'package:easy_queue/easy_queue.dart';
import 'package:easy_queue/src/models/queue_snapshot.dart';
import 'package:flutter/widgets.dart';

class EasyQueueWidget<T> extends StatefulWidget {
  const EasyQueueWidget({
    super.key,
    required this.queue,
    required this.builder,
  });

  /// The queue to listen to.
  final EasyQueue<T> queue;

  /// The builder function that will be called when the queue updates.
  final Widget Function(BuildContext context, QueueSnapshot? snapshot) builder;

  @override
  State<EasyQueueWidget<T>> createState() => _EasyQueueWidgetState<T>();
}

class _EasyQueueWidgetState<T> extends State<EasyQueueWidget<T>> {
  StreamSubscription<QueueSnapshot<T>>? _onUpdateSubscription;
  QueueSnapshot? _lastSnapshot;

  @override
  void initState() {
    _onUpdateSubscription = widget.queue.onUpdate.listen((item) {
      setState(() {
        _lastSnapshot = item;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    _onUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _lastSnapshot);
  }
}
