import 'dart:async';

import 'package:easy_queue/easy_queue.dart';
import 'package:flutter/widgets.dart';

/// This widget calls the `builder` function whenever the queue is updated.
class EasyQueueWidget<T> extends StatefulWidget {
  const EasyQueueWidget({
    super.key,
    required this.queue,
    required this.builder,
  });

  final EasyQueue<T> queue;
  final Widget Function(BuildContext context) builder;

  @override
  State<EasyQueueWidget<T>> createState() => _EasyQueueWidgetState<T>();
}

class _EasyQueueWidgetState<T> extends State<EasyQueueWidget<T>> {
  StreamSubscription<String>? _onStartSubscription;
  StreamSubscription<QueueItem<T>>? _onUpdateSubscription;
  StreamSubscription<Iterable<QueueItem<T>>>? _onDoneSubscription;

  @override
  void initState() {
    _onStartSubscription = widget.queue.onStart.listen((batchId) {
      setState(() {});
    });
    _onUpdateSubscription = widget.queue.onUpdate.listen((item) {
      setState(() {});
    });
    _onDoneSubscription = widget.queue.onDone.listen((items) {
      setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    _onStartSubscription?.cancel();
    _onUpdateSubscription?.cancel();
    _onDoneSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }
}
