import 'dart:async';

import 'package:easy_queue/src/models/queue_item.dart';

typedef ItemHandler<T> = FutureOr<void> Function(QueueItem<T> item);
