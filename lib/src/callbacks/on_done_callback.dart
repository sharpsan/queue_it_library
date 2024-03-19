import 'dart:async';

import 'package:easy_queue/src/models/queue_item.dart';

typedef OnDoneCallback<T> = FutureOr<void> Function(
  Iterable<QueueItem<T>> processedItems,
);
