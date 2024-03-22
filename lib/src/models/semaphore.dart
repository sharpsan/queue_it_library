import 'dart:async';

import 'dart:collection';

class Semaphore {
  Semaphore(this.concurrency);

  final int concurrency;
  int _counter = 0;
  final _queue = Queue<Completer>();

  Future<void> acquire() {
    final completer = Completer();
    if (_counter < concurrency) {
      _counter++;
      completer.complete();
    } else {
      _queue.add(completer);
    }
    return completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _counter--;
    }
  }
}
