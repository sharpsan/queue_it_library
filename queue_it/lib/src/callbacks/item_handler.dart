import 'dart:async';

import 'package:queue_it/src/models/queue_item.dart';

/// Processes one item of a queue.
///
/// The item succeeds when the handler returns, or its future completes, and
/// fails when it throws. The item is the queue's live item: the handler can
/// check `item.status` to see whether the item was canceled or removed while
/// it ran, and set `item.nextStatus` to choose what happens next.
typedef ItemHandler<T> = FutureOr<void> Function(QueueItem<T> item);
