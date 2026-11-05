import 'package:queue_it/src/models/queue_item.dart';
import 'package:queue_it/src/models/queue_item_status.dart';

/// A callback for an item's status. Nothing in queue_it uses it.
@Deprecated('Unused. Listen to QueueIt.onUpdate instead.')
typedef OnUpdateCallback<T> = void Function(
  QueueItemStatus status,
  QueueItem<T> item,
);
