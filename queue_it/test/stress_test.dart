import 'dart:async';
import 'dart:math';

import 'package:queue_it/queue_it.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The statuses each status can move to.
const _transitions = {
  QueueItemStatus.pending: {
    QueueItemStatus.processing,
    QueueItemStatus.canceled,
    QueueItemStatus.removed,
  },
  QueueItemStatus.processing: {
    QueueItemStatus.completed,
    QueueItemStatus.failed,
    QueueItemStatus.canceled,
    QueueItemStatus.removed,
  },
  // A listener can cancel an item in the failed event of an attempt that
  // would be retried.
  QueueItemStatus.failed: {
    QueueItemStatus.pending,
    QueueItemStatus.canceled,
    QueueItemStatus.removed,
  },
  QueueItemStatus.completed: {QueueItemStatus.removed},
  QueueItemStatus.canceled: {QueueItemStatus.removed},
  QueueItemStatus.removed: <QueueItemStatus>{},
};

/// Thrown by the handler for errors that `retryIf` rejects.
class _Fatal implements Exception {}

/// Runs a queue with a random configuration while making random calls to it,
/// from outside and from listeners, and checks every guarantee the queue
/// makes along the way and at the end.
Future<void> _run(int seed) async {
  final random = Random(seed);
  final parallel = 1 + random.nextInt(4);
  final retries = random.nextInt(4);
  final useRetryDelay = random.nextBool();
  final useRetryIf = random.nextBool();

  var running = 0;
  var maxRunning = 0;
  var listenersMayCall = true;
  final problems = <String>[];

  /// Each item's status, as the events have told it.
  final statuses = <String, QueueItemStatus>{};

  /// The ids in the order the queue added the items. A listener can add an
  /// item while another is being added, so this follows the events.
  final addOrder = <String>[];

  /// Each attempt's outcome by item, in order: null for success, or the error.
  final attempts = <String, List<Object?>>{};

  /// What waitFor gives for each item. A listener can remove an item before
  /// add returns, and then there's nothing to wait for.
  final waiters = <String, Future<QueueItem<int>>>{};
  var added = 0;

  /// The items whose last event was the failure of an attempt that will be
  /// retried.
  final retrying = <String>{};

  /// Lets other code run: usually only what's ready now, sometimes timers.
  Future<void> pause() => wait(random.nextInt(5) == 0 ? 1 : 0);

  late final QueueIt<int> queue;
  queue = QueueIt<int>(
    parallel: parallel,
    retries: retries,
    retryDelay: useRetryDelay
        ? (retry) => Duration(milliseconds: random.nextInt(2))
        : null,
    retryIf: useRetryIf ? (error) => error is! _Fatal : null,
    deepCopyItemsInSnapshot: random.nextBool(),
    itemHandler: (item) async {
      running++;
      maxRunning = max(maxRunning, running);
      if (statuses[item.id] != QueueItemStatus.processing) {
        problems.add('${item.id} started as ${statuses[item.id]}');
      }
      if (item.status != QueueItemStatus.processing) {
        problems.add('${item.id} reached its handler as ${item.status}');
      }
      final outcomes = attempts.putIfAbsent(item.id, () => []);
      try {
        await pause();
        final roll = random.nextInt(10);
        if (roll < 3) {
          final error = StateError('flaky');
          outcomes.add(error);
          throw error;
        }
        if (roll < 4) {
          final error = _Fatal();
          outcomes.add(error);
          throw error;
        }
        outcomes.add(null);
      } finally {
        running--;
      }
    },
  );
  addTearDown(queue.dispose);

  var isStarted = false;
  var isProcessing = false;
  queue.onUpdate.listen((snapshot) {
    final item = snapshot.eventItem;
    switch (snapshot.event) {
      case QueueEvent.startedQueue:
        if (isStarted) problems.add('started twice');
        isStarted = true;
      case QueueEvent.stoppedQueue:
        if (!isStarted) problems.add('stopped twice');
        isStarted = false;
      case QueueEvent.startedProcessing:
        if (isProcessing) problems.add('started processing twice');
        isProcessing = true;
      case QueueEvent.stoppedProcessing:
        if (!isProcessing) problems.add('stopped processing twice');
        if (running > 0) {
          problems.add('stopped processing with $running running');
        }
        isProcessing = false;
      case QueueEvent.itemAdded:
        if (item!.status != QueueItemStatus.pending) {
          problems.add('${item.id} added as ${item.status}');
        }
        statuses[item.id] = item.status;
        addOrder.add(item.id);
      case QueueEvent.itemStatusUpdated || QueueEvent.itemRemoved:
        final from = statuses[item!.id]!;
        retrying.remove(item.id);
        if (item.status == QueueItemStatus.failed &&
            item.retryCount < retries &&
            !(useRetryIf && item.error is _Fatal)) {
          retrying.add(item.id);
        }
        if (!_transitions[from]!.contains(item.status)) {
          problems.add('${item.id} went from $from to ${item.status}');
        }
        if (from == QueueItemStatus.failed &&
            item.status == QueueItemStatus.canceled &&
            (item.retryCount >= retries ||
                (useRetryIf && item.error is _Fatal))) {
          problems.add('${item.id} was canceled after its last attempt');
        }
        statuses[item.id] = item.status;
      case QueueEvent.cancelledAll:
        statuses.updateAll((id, status) => status == QueueItemStatus.pending ||
                status == QueueItemStatus.processing ||
                retrying.contains(id)
            ? QueueItemStatus.canceled
            : status);
        retrying.clear();
      case QueueEvent.removedAll:
        statuses.updateAll((id, status) => QueueItemStatus.removed);
        retrying.clear();
    }
    if (snapshot.isStarted != isStarted) {
      problems
          .add('${snapshot.event.name} said isStarted ${snapshot.isStarted}');
    }
    if (snapshot.isProcessing != isProcessing) {
      problems.add(
          '${snapshot.event.name} said isProcessing ${snapshot.isProcessing}');
    }
  });

  String add() {
    final id = queue.add(added++);
    if (queue.hasItemById(id)) waiters[id] = queue.waitFor(id);
    return id;
  }

  String randomId() => addOrder[random.nextInt(addOrder.length)];

  // A second listener that calls the queue now and then, with every method
  // but dispose.
  queue.onUpdate.listen((snapshot) {
    if (!listenersMayCall) return;
    final item = snapshot.eventItem;
    final roll = random.nextInt(200);
    if (roll < 4 && added < 150) {
      add();
    } else if (roll < 8) {
      queue.cancelById(randomId());
    } else if (roll < 10) {
      queue.removeById(randomId());
    } else if (roll < 12 && item?.status == QueueItemStatus.failed) {
      queue.removeById(item!.id);
    } else if (roll < 14 && item?.status == QueueItemStatus.failed) {
      queue.cancelById(item!.id);
    } else if (roll < 16) {
      queue.stop();
    } else if (roll < 19) {
      queue.start(stopAutomatically: random.nextBool());
    } else if (roll < 20) {
      queue
        ..stop()
        ..start(stopAutomatically: random.nextBool());
    } else if (roll < 21) {
      queue.cancelAll();
    } else if (roll < 22 && random.nextInt(4) == 0) {
      queue.removeAll();
    }
  });

  for (var i = 0; i < 20; i++) {
    add();
  }
  for (var step = 0; step < 150; step++) {
    final roll = random.nextInt(100);
    if (roll < 25) {
      add();
    } else if (roll < 35) {
      queue.cancelById(randomId());
    } else if (roll < 42) {
      queue.removeById(randomId());
    } else if (roll < 43) {
      queue.cancelAll();
    } else if (roll < 44) {
      queue.removeAll();
    } else if (roll < 50) {
      queue.stop();
    } else if (roll < 62) {
      queue.start(stopAutomatically: random.nextBool());
    } else if (roll < 66) {
      queue
        ..stop()
        ..start(stopAutomatically: random.nextBool());
    }
    await pause();
  }

  // Let the queue finish, without any more calls.
  listenersMayCall = false;
  queue
    ..stop()
    ..start();
  final results = {
    for (final MapEntry(:key, :value) in waiters.entries)
      key: await value.timeout(const Duration(seconds: 10)),
  };
  queue.stop();
  await queue.running.timeout(const Duration(seconds: 10));

  final context = 'seed $seed, parallel $parallel, retries $retries, '
      'retryDelay $useRetryDelay, retryIf $useRetryIf';
  expect(problems, isEmpty, reason: context);
  expect(maxRunning, lessThanOrEqualTo(parallel), reason: context);
  expect(running, 0, reason: context);
  expect(queue.isStarted, isFalse, reason: context);
  expect(queue.isProcessing, isFalse, reason: context);

  // The queue holds every item that wasn't removed, in the order added.
  expect(
    [for (final item in queue.items()) item.id],
    [
      for (final id in addOrder)
        if (statuses[id] != QueueItemStatus.removed) id,
    ],
    reason: context,
  );

  for (final id in addOrder) {
    final status = statuses[id]!;
    final outcomes = attempts[id] ?? const [];
    final itemContext = '$context, item $id: $outcomes';
    final result = results[id];
    if (result == null) {
      expect(status, QueueItemStatus.removed, reason: itemContext);
      expect(outcomes, isEmpty, reason: itemContext);
      continue;
    }
    // waitFor gives the status the item finished with. A finished item can
    // be removed afterwards.
    if (status != QueueItemStatus.removed) {
      expect(result.status, status, reason: itemContext);
      expect(queue.items().singleWhere((item) => item.id == id).status, status,
          reason: itemContext);
    }
    switch (result.status) {
      case QueueItemStatus.completed:
        expect(outcomes.last, isNull, reason: itemContext);
      case QueueItemStatus.failed:
        // The last attempt failed, and the queue retried while it could.
        expect(outcomes.last, isNotNull, reason: itemContext);
        expect(result.error, same(outcomes.last), reason: itemContext);
        expect(result.stackTrace, isNotNull, reason: itemContext);
        if (!(useRetryIf && outcomes.last is _Fatal)) {
          expect(outcomes, hasLength(retries + 1), reason: itemContext);
        }
      case QueueItemStatus.canceled || QueueItemStatus.removed:
        break;
      case QueueItemStatus.pending || QueueItemStatus.processing:
        fail('$itemContext: unfinished');
    }
    // Every attempt but the last failed with an error worth retrying.
    for (final outcome in outcomes.take(max(0, outcomes.length - 1))) {
      expect(outcome, isNotNull, reason: itemContext);
      if (useRetryIf) {
        expect(outcome, isNot(isA<_Fatal>()), reason: itemContext);
      }
    }
    expect(outcomes.length, lessThanOrEqualTo(retries + 1),
        reason: itemContext);
  }
}

void main() {
  for (var seed = 1; seed <= 40; seed++) {
    test(
        'keeps its guarantees under random use (seed $seed)', () => _run(seed));
  }
}
