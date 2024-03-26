import 'package:queue_it/queue_it.dart';
import 'package:flutter/widgets.dart';

class QueueItWidget<T> extends StatefulWidget {
  const QueueItWidget({
    super.key,
    required this.queue,
    required this.builder,
  });

  /// The queue to listen to.
  final QueueIt<T> queue;

  /// The builder function that will be called when the queue updates.
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
