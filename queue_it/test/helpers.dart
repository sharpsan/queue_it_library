import 'dart:async';

import 'package:queue_it/queue_it.dart';

/// Waits [ms] milliseconds, or for the queued microtasks when [ms] is 0.
Future<void> wait([int ms = 0]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Records the events a queue sends, as `event` or `event:data:status`.
List<String> recordEvents<T>(QueueIt<T> queue) {
  final events = <String>[];
  queue.onUpdate.listen((snapshot) {
    final item = snapshot.eventItem;
    events.add(item == null
        ? snapshot.event.name
        : '${snapshot.event.name}:${item.data}:${item.status.name}');
  });
  return events;
}

/// The data and status of each item, as `data:status`.
List<String> statuses<T>(QueueIt<T> queue) =>
    [for (final item in queue.items()) '${item.data}:${item.status.name}'];

/// A handler whose items wait until [release] is called with their data.
class Gate<T> {
  final _completers = <T, Completer<void>>{};

  /// The data of the items whose handler is running, in the order they
  /// started.
  final started = <T>[];

  Future<void> call(QueueItem<T> item) {
    started.add(item.data);
    return (_completers[item.data] = Completer<void>()).future;
  }

  /// Lets the item with [data] finish, or fail with [error].
  void release(T data, [Object? error]) {
    final completer = _completers.remove(data)!;
    error == null ? completer.complete() : completer.completeError(error);
  }
}
