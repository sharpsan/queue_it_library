import 'package:easy_queue/easy_queue.dart';
import 'package:flutter/widgets.dart';

class EasyQueueWidget<T> extends StatefulWidget {
  const EasyQueueWidget({
    super.key,
    required this.queue,
    required this.builder,
  });
  final EasyQueue<T> queue;
  final Widget Function(bool processing) builder;

  @override
  State<EasyQueueWidget<T>> createState() => _EasyQueueWidgetState<T>();
}

class _EasyQueueWidgetState<T> extends State<EasyQueueWidget<T>> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.queue.isProcessingNotifier,
      builder: (context, isProcessing, child) {
        return widget.builder(isProcessing);
      },
    );
  }
}
