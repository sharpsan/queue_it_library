import 'dart:async';

import 'package:queue_it/src/models/queue_item.dart';

typedef ItemHandler<T> = FutureOr<void> Function(QueueItem<T> item);
