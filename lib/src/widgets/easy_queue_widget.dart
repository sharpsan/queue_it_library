import 'package:easy_queue/easy_queue.dart';
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
