import 'package:easy_queue/src/models/queue_item.dart';

typedef OnDoneCallback<T> = void Function(
  Iterable<QueueItem<T>> processedItems,
);
