import 'dart:async';

import 'package:queue_it/queue_it.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('processes items in the order they were added', () async {
    final processed = <int>[];
    final queue = QueueIt<int>(itemHandler: (item) => processed.add(item.data));
    addTearDown(queue.dispose);
    for (var i = 0; i < 10; i++) {
      queue.add(i);
    }

    queue.start();
    await queue.running;

    expect(processed, List.generate(10, (i) => i));
  });

  test(
      'keeps the order when a listener stops the queue as the first item is '
      'about to start', () async {
    final processed = <int>[];
    final queue = QueueIt<int>(itemHandler: (item) => processed.add(item.data));
    addTearDown(queue.dispose);
    var stopped = false;
    queue.onUpdate.listen((snapshot) {
      if (snapshot.event == QueueEvent.startedProcessing && !stopped) {
        stopped = true;
        queue.stop();
      }
    });
    queue
      ..add(1)
      ..add(2)
      ..add(3)
      ..start();
    await queue.running;
    expect(processed, isEmpty);

    queue.start();
    await queue.running;

    expect(processed, [1, 2, 3]);
  });

  test('starts items in order when processing several at once', () async {
    final gate = Gate<int>();
    final queue = QueueIt<int>(parallel: 3, itemHandler: gate.call);
    addTearDown(queue.dispose);
    for (var i = 0; i < 6; i++) {
      queue.add(i);
    }

    queue.start();
    await wait();
    expect(gate.started, [0, 1, 2]);

    gate.release(1);
    await wait();
    expect(gate.started, [0, 1, 2, 3]);
  });

  test('never processes more than parallel items at once', () async {
    var running = 0, maxRunning = 0;
    final queue = QueueIt<int>(
      parallel: 2,
      itemHandler: (item) async {
        running++;
        if (running > maxRunning) maxRunning = running;
        await wait(5);
        running--;
      },
    );
    addTearDown(queue.dispose);
    for (var i = 0; i < 10; i++) {
      queue.add(i);
    }

    queue.start();
    await queue.running;

    expect(maxRunning, 2);
    expect(queue.items().completed, hasLength(10));
  });

  test('keeps the parallel limit when stopped and started again at once',
      () async {
    final gate = Gate<int>();
    final queue = QueueIt<int>(parallel: 2, itemHandler: gate.call);
    addTearDown(queue.dispose);
    for (var i = 0; i < 6; i++) {
      queue.add(i);
    }
    queue.start();
    await wait();

    queue
      ..stop()
      ..start();
    await wait();
    expect(gate.started, [0, 1]);

    gate.release(0);
    await wait();
    expect(gate.started, [0, 1, 2]);
  });

  test(
      'carries on with the same run when started again before its handlers '
      'have returned', () async {
    final gate = Gate<int>();
    final queue = QueueIt<int>(itemHandler: gate.call);
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..start();
    await wait();
    queue.stop();
    var stopped = false;
    final running = queue.running.then((_) => stopped = true);

    queue.start();
    await wait(10);
    // The handler of 1 is still running.
    expect(stopped, isFalse);

    gate.release(1);
    await running.timeout(const Duration(seconds: 1));
    expect(queue.isStarted, isFalse);
    expect(statuses(queue), ['1:completed']);
  });

  test('stops by itself once every item is processed', () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    final events = recordEvents(queue);
    queue.add(1);

    queue.start();
    await queue.running;

    expect(queue.isStarted, isFalse);
    expect(queue.isProcessing, isFalse);
    expect(events, [
      'itemAdded:1:pending',
      'startedQueue',
      'startedProcessing',
      'itemStatusUpdated:1:processing',
      'itemStatusUpdated:1:completed',
      'stoppedProcessing',
      'stoppedQueue',
    ]);
  });

  test('does nothing when started while started', () async {
    final handled = <int>[];
    final queue = QueueIt<int>(itemHandler: (item) async {
      handled.add(item.data);
      await wait();
    });
    addTearDown(queue.dispose);
    final events = recordEvents(queue);
    queue
      ..add(1)
      ..add(2)
      ..start();
    await wait();
    queue
      ..start()
      ..start(stopAutomatically: false);
    await queue.running;

    expect(handled, [1, 2]);
    expect(events.where((event) => event == 'startedQueue'), hasLength(1));
    // The first start's stopAutomatically still applies.
    expect(queue.isStarted, isFalse);
  });

  test('records the times in order', () async {
    final queue = QueueIt<int>(parallel: 2, itemHandler: (item) => wait(1));
    addTearDown(queue.dispose);
    late QueueSnapshot<int> last;
    queue.onUpdate.listen((snapshot) => last = snapshot);
    for (var i = 0; i < 5; i++) {
      queue.add(i);
    }

    queue.start();
    await queue.running;

    final times = [
      last.startedAt!,
      last.startedProcessingAt!,
      for (final item in last.items) item.startedProcessingAt!,
      last.stoppedProcessingAt!,
      last.stoppedAt!,
    ];
    for (var i = 0; i < times.length - 1; i++) {
      expect(times[i].isAfter(times[i + 1]), isFalse, reason: 'time $i');
    }
  });

  test('waits for its first item when started with none', () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    var stopped = false;

    queue.start();
    queue.running.then((_) => stopped = true);
    await wait(10);
    expect(queue.isStarted, isTrue);
    expect(stopped, isFalse);

    queue.add(1);
    await queue.running;
    expect(statuses(queue), ['1:completed']);
  });

  test('leaves items added after it stopped by itself for the next start',
      () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..start();
    await queue.running;

    queue.add(2);
    await wait(10);
    expect(statuses(queue), ['1:completed', '2:pending']);

    queue.start();
    await queue.running;
    expect(statuses(queue), ['1:completed', '2:completed']);
  });

  test('keeps processing items added later when it does not stop by itself',
      () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..start(stopAutomatically: false);
    await wait(10);
    expect(queue.isStarted, isTrue);
    expect(queue.isProcessing, isFalse);

    queue.add(2);
    await wait(10);
    expect(statuses(queue), ['1:completed', '2:completed']);

    queue.stop();
    await queue.running;
  });

  test('refuses a parallel below 1 and negative retries', () {
    expect(() => QueueIt<int>(parallel: 0, itemHandler: (item) {}),
        throwsArgumentError);
    expect(() => QueueIt<int>(retries: -1, itemHandler: (item) {}),
        throwsArgumentError);
  });

  test('handles a long run of handlers that throw right away', () async {
    // Not async: the handler throws before returning a future.
    final queue = QueueIt<int>(
      itemHandler: (item) => throw FormatException('bad ${item.data}'),
    );
    addTearDown(queue.dispose);
    queue.onUpdate.listen((snapshot) {});
    for (var i = 0; i < 20000; i++) {
      queue.add(i);
    }

    queue.start();
    await queue.running.timeout(const Duration(seconds: 30));

    expect(queue.isProcessing, isFalse);
    expect(queue.items().failed, hasLength(20000));
  });

  test("settles a microtask later when the handler's future calls back at once",
      () async {
    final queue = QueueIt<int>(itemHandler: (item) => _SynchronousFuture());
    addTearDown(queue.dispose);
    final events = recordEvents(queue);
    // Whether an item finished, or the next one started, inside `then`.
    var insideThen = false;
    queue.onUpdate.listen((snapshot) {
      if (_SynchronousFuture.calling > 0) insideThen = true;
    });
    queue
      ..add(1)
      ..add(2)
      ..start();

    await queue.running;

    expect(insideThen, isFalse);
    expect(events, [
      'itemAdded:1:pending',
      'itemAdded:2:pending',
      'startedQueue',
      'startedProcessing',
      'itemStatusUpdated:1:processing',
      'itemStatusUpdated:1:completed',
      'itemStatusUpdated:2:processing',
      'itemStatusUpdated:2:completed',
      'stoppedProcessing',
      'stoppedQueue',
    ]);
  });

  test('processes an item added as processing stops', () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    queue.onUpdate.listen((snapshot) {
      if (snapshot.event == QueueEvent.stoppedProcessing &&
          queue.items().length == 1) {
        queue.add(2);
      }
    });

    queue
      ..add(1)
      ..start();
    await queue.running;

    expect(statuses(queue), ['1:completed', '2:completed']);
    expect(queue.isStarted, isFalse);
  });

  test('waits for items when a listener starts it again as it stops', () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    var restarted = false;
    queue.onUpdate.listen((snapshot) {
      if (snapshot.event == QueueEvent.stoppedProcessing && !restarted) {
        restarted = true;
        queue
          ..stop()
          ..start();
      }
    });
    queue
      ..add(1)
      ..start();
    await wait(10);
    expect(queue.isStarted, isTrue);

    queue.add(2);
    await queue.running;

    expect(statuses(queue), ['1:completed', '2:completed']);
    expect(queue.isStarted, isFalse);
  });

  test('completes running when a listener starts it again as it stops',
      () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    var restarted = false;
    queue.onUpdate.listen((snapshot) {
      if (snapshot.event == QueueEvent.stoppedQueue && !restarted) {
        restarted = true;
        queue.start();
      }
    });
    queue
      ..add(1)
      ..start();

    await queue.running.timeout(const Duration(seconds: 1));
    expect(restarted, isTrue);
    expect(queue.isStarted, isTrue);
  });

  test('completes running for a queue that was never started', () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    queue.add(1);

    await queue.running.timeout(const Duration(seconds: 1));
  });

  test(
      'stops by itself when its items are canceled or removed before it '
      'gets to them', () async {
    final queue = QueueIt<int>(itemHandler: (item) {});
    addTearDown(queue.dispose);
    final events = recordEvents(queue);
    final first = queue.add(1);
    final second = queue.add(2);

    queue
      ..start()
      ..cancelById(first)
      ..removeById(second);

    await queue.running.timeout(const Duration(seconds: 1));
    expect(queue.isStarted, isFalse);
    expect(events, [
      'itemAdded:1:pending',
      'itemAdded:2:pending',
      'startedQueue',
      'itemStatusUpdated:1:canceled',
      'itemRemoved:2:removed',
      'stoppedQueue',
    ]);
  });

  group('stop', () {
    test('lets running items finish and leaves the rest pending', () async {
      final gate = Gate<int>();
      final queue = QueueIt<int>(itemHandler: gate.call);
      addTearDown(queue.dispose);
      final events = recordEvents(queue);
      queue
        ..add(1)
        ..add(2)
        ..start();
      await wait();

      queue.stop();
      var stopped = false;
      queue.running.then((_) => stopped = true);
      await wait();
      expect(queue.isStarted, isFalse);
      expect(queue.isProcessing, isTrue);
      expect(stopped, isFalse);

      gate.release(1);
      await wait();
      expect(stopped, isTrue);
      expect(queue.isProcessing, isFalse);
      expect(statuses(queue), ['1:completed', '2:pending']);
      expect(events.skip(4), [
        'itemStatusUpdated:1:processing',
        'stoppedQueue',
        'itemStatusUpdated:1:completed',
        'stoppedProcessing',
      ]);
    });

    test('completes running right away when nothing is running', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      addTearDown(queue.dispose);
      queue
        ..add(1)
        ..start(stopAutomatically: false);
      await wait(10);

      queue.stop();
      await queue.running;
      expect(queue.isProcessing, isFalse);
    });

    test('lets start pick up the pending items again', () async {
      final gate = Gate<int>();
      final queue = QueueIt<int>(itemHandler: gate.call);
      addTearDown(queue.dispose);
      queue
        ..add(1)
        ..add(2)
        ..start();
      await wait();
      queue.stop();
      gate.release(1);
      await queue.running;

      queue.start();
      await wait();
      gate.release(2);
      await queue.running;

      expect(statuses(queue), ['1:completed', '2:completed']);
    });
  });

  group('dispose', () {
    test('ignores the outcome of running handlers', () async {
      final gate = Gate<int>();
      final queue = QueueIt<int>(itemHandler: gate.call);
      queue
        ..add(1)
        ..start();
      await wait();

      queue.dispose();
      await queue.running;
      gate.release(1);
      await wait();

      expect(statuses(queue), ['1:processing']);
    });

    test('closes onUpdate', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      var closed = false;
      queue.onUpdate.listen(null, onDone: () => closed = true);

      queue.dispose();

      expect(closed, isTrue);
    });

    test('refuses new items and starts', () {
      final queue = QueueIt<int>(itemHandler: (item) {})..dispose();

      expect(() => queue.add(1), throwsStateError);
      expect(queue.start, throwsStateError);
      expect(queue.dispose, returnsNormally);
    });

    test('settles isProcessing once the running handlers return', () async {
      final gate = Gate<int>();
      final queue = QueueIt<int>(itemHandler: gate.call);
      queue
        ..add(1)
        ..start();
      await wait();
      expect(queue.isProcessing, isTrue);

      queue.dispose();
      gate.release(1);
      await wait();

      expect(queue.isProcessing, isFalse);
    });

    test(
        'settles isProcessing when a listener disposes it as processing '
        'starts', () async {
      final queue = QueueIt<int>(itemHandler: (item) {});
      queue.onUpdate.listen((snapshot) {
        if (snapshot.event == QueueEvent.startedProcessing) queue.dispose();
      });
      queue
        ..add(1)
        ..start();
      await wait();

      expect(queue.isStarted, isFalse);
      expect(queue.isProcessing, isFalse);
      expect(statuses(queue), ['1:pending']);
    });

    test("can't be started again by a listener", () {
      final queue = QueueIt<int>(itemHandler: (item) {});
      final errors = <Object>[];
      queue.onUpdate.listen((snapshot) {
        if (snapshot.event == QueueEvent.stoppedQueue) {
          try {
            queue.start();
          } on StateError catch (error) {
            errors.add(error);
          }
        }
      });
      queue.start(stopAutomatically: false);

      queue.dispose();

      expect(queue.isStarted, isFalse);
      expect(errors, [isA<StateError>()]);
    });
  });

  test('stops by itself once a retry it was restarted for is canceled',
      () async {
    final queue = QueueIt<int>(
      retries: 1,
      retryDelay: (retry) => const Duration(milliseconds: 50),
      itemHandler: (item) => throw Exception('failed'),
    );
    addTearDown(queue.dispose);
    // Restarted as the first attempt fails.
    queue.onUpdate.listen((snapshot) {
      final item = snapshot.eventItem;
      if (item?.status == QueueItemStatus.failed && item!.retryCount == 0) {
        queue
          ..stop()
          ..start();
      }
    });
    final id = queue.add(1);
    queue.start();
    await wait(10);
    expect(queue.isStarted, isTrue);

    expect(queue.cancelById(id), isTrue);

    await queue.running.timeout(const Duration(seconds: 1));
    expect(queue.isStarted, isFalse);
  });

  test('waits for items when started while only a canceled handler runs',
      () async {
    final gate = Gate<int>();
    final queue = QueueIt<int>(itemHandler: gate.call);
    addTearDown(queue.dispose);
    final first = queue.add(1);
    queue.start();
    await wait();
    queue
      ..stop()
      ..cancelById(first)
      ..start();

    gate.release(1);
    await wait(10);

    expect(queue.isStarted, isTrue);
    queue.add(2);
    await wait();
    expect(gate.started, [1, 2]);
    gate.release(2);
  });

  test("doesn't start a handler once a listener disposes the queue", () async {
    final started = <int>[];
    final queue = QueueIt<int>(itemHandler: (item) => started.add(item.data));
    queue.onUpdate.listen((snapshot) {
      if (snapshot.eventItem?.status == QueueItemStatus.processing) {
        queue.dispose();
      }
    });

    queue
      ..add(1)
      ..start();
    await wait();

    expect(started, isEmpty);
    expect(queue.isProcessing, isFalse);
  });
}

/// A future that calls back before `then` returns, as Flutter's
/// SynchronousFuture does.
class _SynchronousFuture implements Future<void> {
  /// How many `then` calls are running.
  static var calling = 0;

  @override
  Future<R> then<R>(FutureOr<R> Function(void value) onValue,
      {Function? onError}) {
    calling++;
    try {
      final result = onValue(null);
      return result is Future<R> ? result : Future<R>.value(result);
    } finally {
      calling--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
