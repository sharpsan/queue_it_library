import 'dart:async';

import 'package:easy_queue/src/models/queue_item.dart';
import 'package:easy_queue/src/models/queue_item_status.dart';

typedef ItemHandler<T> = FutureOr<QueueItemStatus?> Function(QueueItem<T> item);
