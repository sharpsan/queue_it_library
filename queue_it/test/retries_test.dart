import 'dart:async';

import 'package:queue_it/queue_it.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('retries a failing item, then marks it failed with the error', () async {
    var attempts = 0;
    final queue = QueueIt<int>(
      retries: 3,
      itemHandler: (item) {
        attempts++;
        throw StateError('attempt $attempts');
      },
    );
    addTearDown(queue.dispose);
    final events = recordEvents(queue);
    queue
      ..add(1)
      ..start();
    await queue.running;

    final item = queue.items().single;
    expect(attempts, 4);
    expect(item.status, QueueItemStatus.failed);
    expect(item.retryCount, 3);
    expect(item.error, isA<StateError>());
    expect((item.error as StateError).message, 'attempt 4');
    expect(item.stackTrace, isNotNull);
    expect(item.failedAt, isNotNull);
    expect(queue.items().failed, [item]);
    expect(events.where((event) => event.startsWith('itemStatusUpdated')), [
      for (var i = 0; i < 4; i++) ...[
        if (i > 0) 'itemStatusUpdated:1:pending',
        'itemStatusUpdated:1:processing',
        'itemStatusUpdated:1:failed',
      ],
    ]);
  });

  test('completes an item that succeeds on a retry, keeping the error',
      () async {
    final queue = QueueIt<int>(
      retries: 3,
      itemHandler: (item) {
        if (item.retryCount < 2) throw Exception('flaky');
      },
    );
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..start();
    await queue.running;

    final item = queue.items().single;
    expect(item.status, QueueItemStatus.completed);
    expect(item.retryCount, 2);
    expect(item.error, isException);
  });

  test('retries a failed item before the items waiting after it', () async {
    final processed = <String>[];
    final queue = QueueIt<int>(
      retries: 1,
      itemHandler: (item) {
        processed.add('${item.data}.${item.retryCount}');
        if (item.data == 1 && item.retryCount == 0) throw Exception('failed');
      },
    );
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..add(2)
      ..start();
    await queue.running;

    expect(processed, ['1.0', '1.1', '2.0']);
  });

  test('retries items in the order their retries are due', () async {
    final processed = <String>[];
    final gate = Gate<int>();
    final queue = QueueIt<int>(
      retries: 1,
      retryDelay: (item, retry) => const Duration(milliseconds: 20),
      itemHandler: (item) {
        processed.add('${item.data}.${item.retryCount}');
        if (item.data == 3) return gate(item);
        if (item.data < 3 && item.retryCount == 0) throw Exception('failed');
      },
    );
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..add(2)
      ..add(3)
      ..add(4)
      ..start();
    // Both retries are due while 3 holds the only slot.
    await wait(80);
    expect(processed, ['1.0', '2.0', '3.0']);

    gate.release(3);
    await queue.running;

    expect(processed, ['1.0', '2.0', '3.0', '1.1', '2.1', '4.0']);
  });

  test('retries items that failed while stopped in the order they failed',
      () async {
    final processed = <String>[];
    final gate = Gate<int>();
    final queue = QueueIt<int>(
      parallel: 2,
      retries: 1,
      itemHandler: (item) {
        processed.add('${item.data}.${item.retryCount}');
        if (item.retryCount == 0) return gate(item);
      },
    );
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..add(2)
      ..add(3)
      ..start();
    await wait();
    queue.stop();
    gate
      ..release(1, Exception('failed'))
      ..release(2, Exception('failed'));
    await queue.running;

    queue.start();
    await wait();
    gate.release(3);
    await queue.running;

    expect(processed, ['1.0', '2.0', '1.1', '2.1', '3.0']);
  });

  test(
      'keeps a retry ahead of the others when a listener stops the queue as '
      'it is about to start', () async {
    final attempts = <int>[];
    final queue = QueueIt<int>(
      retries: 1,
      retryDelay: (item, retry) => const Duration(milliseconds: 20),
      itemHandler: (item) {
        attempts.add(item.data);
        if (item.retryCount == 0) throw Exception('failed');
      },
    );
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..add(2)
      ..start(stopAutomatically: false);
    await wait(5);
    expect(attempts, [1, 2]);
    queue.stop();
    // Both retries come due while the queue is stopped.
    await wait(80);
    var stopped = false;
    queue.onUpdate.listen((snapshot) {
      if (snapshot.event == QueueEvent.startedProcessing && !stopped) {
        stopped = true;
        queue.stop();
      }
    });
    queue.start();
    await queue.running;
    expect(attempts, [1, 2]);

    queue.start();
    await queue.running;

    expect(attempts, [1, 2, 1, 2]);
    expect(statuses(queue), ['1:completed', '2:completed']);
  });

  test('fails an item without retrying when retryIf says no', () async {
    final errors = <Object>[];
    final queue = QueueIt<int>(
      retries: 3,
      retryIf: (item, error) {
        errors.add(error);
        return error is! ArgumentError;
      },
      itemHandler: (item) {
        throw item.data == 1 ? ArgumentError('bad data') : Exception('flaky');
      },
    );
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..add(2)
      ..start();
    await queue.running;

    expect(queue.items().map((item) => item.retryCount), [0, 3]);
    expect(statuses(queue), ['1:failed', '2:failed']);
    expect(errors, hasLength(4));
  });

  test('willRetry tells a failure that will be retried from the last one',
      () async {
    final queue = QueueIt<int>(
      retries: 2,
      // Item 2 isn't retried, though it has retries left.
      retryIf: (item, error) => item.data != 2,
      itemHandler: (item) {
        if (item.data != 3 || item.retryCount < 1) throw Exception('failed');
      },
    );
    addTearDown(queue.dispose);
    final seen = <String>[];
    queue.onUpdate.listen((snapshot) {
      final item = snapshot.eventItem;
      if (item != null && snapshot.event == QueueEvent.itemStatusUpdated) {
        seen.add('${item.data}:${item.status.name}:${item.retryCount}'
            '${snapshot.willRetry ? ':willRetry' : ''}');
      } else {
        expect(snapshot.willRetry, isFalse, reason: snapshot.event.name);
      }
    });
    queue
      ..add(1)
      ..add(2)
      ..add(3)
      ..start();
    await queue.running;

    expect(seen, [
      '1:processing:0',
      '1:failed:0:willRetry',
      '1:pending:1',
      '1:processing:1',
      '1:failed:1:willRetry',
      '1:pending:2',
      '1:processing:2',
      '1:failed:2',
      '2:processing:0',
      '2:failed:0',
      '3:processing:0',
      '3:failed:0:willRetry',
      '3:pending:1',
      '3:processing:1',
      '3:completed:1',
    ]);
  });

  test('willRetry is true for a retry that waits for its delay', () async {
    final queue = QueueIt<int>(
      retries: 1,
      retryDelay: (item, retry) => const Duration(milliseconds: 20),
      itemHandler: (item) => throw Exception('failed'),
    );
    addTearDown(queue.dispose);
    final failures = <bool>[];
    queue.onUpdate.listen((snapshot) {
      if (snapshot.eventItem?.status == QueueItemStatus.failed) {
        failures.add(snapshot.willRetry);
      }
    });
    queue
      ..add(1)
      ..start();
    await queue.running;

    expect(failures, [true, false]);
  });

  test('retryIf gets the item that failed', () async {
    final asked = <String>[];
    final queue = QueueIt<int>(
      retries: 1,
      // Only odd items get another try.
      retryIf: (item, error) {
        asked.add('${item.data}:${item.status.name}:${item.retryCount}');
        return item.data.isOdd;
      },
      itemHandler: (item) => throw Exception('failed'),
    );
    addTearDown(queue.dispose);
    queue
      ..add(1)
      ..add(2)
      ..start();
    await queue.running;

    expect(asked, ['1:processing:0', '2:processing:0']);
    expect(queue.items().map((item) => item.retryCount), [1, 0]);
  });

  test(
      'completes waitFor on the failure that is not retried, with retries left',
      () async {
    final failedWith = <int>[];
    final queue = QueueIt<String>(
      retries: 2,
      retryIf: (item, error) => error is! FormatException,
      itemHandler: (item) => throw item.retryCount == 0
          ? StateError('busy')
          : const FormatException('bad file'),
    );
    addTearDown(queue.dispose);
    // To a listener both failures look the same: failed, with retries left.
    queue.onUpdate.listen((snapshot) {
      final item = snapshot.eventItem;
      if (item?.status == QueueItemStatus.failed) {
        failedWith.add(item!.retryCount);
      }
    });
    final finished = queue.waitFor(queue.add('a'));
    queue.start();

    final item = await finished;

    expect(item.status, QueueItemStatus.failed);
    expect(item.error, isFormatException);
    expect(item.retryCount, 1);
    expect(failedWith, [0, 1]);
  });

  group('retryDelay', () {
    test('gets the item and the number of the retry', () async {
      final asked = <String>[];
      final queue = QueueIt<int>(
        retries: 2,
        retryDelay: (item, retry) {
          asked.add('${item.data}:${item.retryCount}:$retry');
          return Duration.zero;
        },
        itemHandler: (item) => throw Exception('failed'),
      );
      addTearDown(queue.dispose);
      queue
        ..add(7)
        ..start();
      await queue.running;

      expect(asked, ['7:0:1', '7:1:2']);
    });

    test('waits before each retry', () async {
      final retries = <int>[];
      final attempts = <DateTime>[];
      final queue = QueueIt<int>(
        retries: 2,
        retryDelay: (item, retry) {
          retries.add(retry);
          return Duration(milliseconds: 20 * retry);
        },
        itemHandler: (item) {
          attempts.add(DateTime.now());
          throw Exception('failed');
        },
      );
      addTearDown(queue.dispose);
      queue
        ..add(1)
        ..start();
      await queue.running;

      expect(retries, [1, 2]);
      expect(attempts, hasLength(3));
      expect(attempts[1].difference(attempts[0]).inMilliseconds,
          greaterThanOrEqualTo(15));
      expect(attempts[2].difference(attempts[1]).inMilliseconds,
          greaterThanOrEqualTo(35));
    });

    test('frees the slot and keeps the queue processing while it waits',
        () async {
      final processed = <String>[];
      final queue = QueueIt<int>(
        retries: 1,
        retryDelay: (item, retry) => const Duration(milliseconds: 30),
        itemHandler: (item) {
          processed.add('${item.data}.${item.retryCount}');
          if (item.data == 1 && item.retryCount == 0) {
            throw Exception('failed');
          }
        },
      );
      addTearDown(queue.dispose);
      queue
        ..add(1)
        ..add(2)
        ..start();
      await wait(10);

      expect(processed, ['1.0', '2.0']);
      expect(queue.items().first.status, QueueItemStatus.pending);
      expect(queue.isProcessing, isTrue);
      expect(queue.isStarted, isTrue);

      await queue.running;
      expect(processed, ['1.0', '2.0', '1.1']);
      expect(statuses(queue), ['1:completed', '2:completed']);
    });

    test('lets a waiting retry be canceled', () async {
      var attempts = 0;
      final queue = QueueIt<int>(
        retries: 1,
        retryDelay: (item, retry) => const Duration(milliseconds: 20),
        itemHandler: (item) {
          attempts++;
          throw Exception('failed');
        },
      );
      addTearDown(queue.dispose);
      final id = queue.add(1);
      queue.start();
      await wait(5);

      expect(queue.cancelById(id), isTrue);
      await queue.running;
      await wait(30);

      expect(attempts, 1);
      expect(statuses(queue), ['1:canceled']);
    });

    test('lets a listener cancel a retry as it is queued', () async {
      var attempts = 0;
      final queue = QueueIt<int>(
        retries: 1,
        retryDelay: (item, retry) => const Duration(hours: 1),
        itemHandler: (item) {
          attempts++;
          throw Exception('failed');
        },
      );
      addTearDown(queue.dispose);
      queue.onUpdate.listen((snapshot) {
        final item = snapshot.eventItem;
        if (item?.status == QueueItemStatus.pending && item!.retryCount == 1) {
          queue.cancel(item);
        }
      });
      queue
        ..add(1)
        ..start();
      // The queue doesn't wait out the canceled retry's delay.
      await queue.running.timeout(const Duration(seconds: 5));

      expect(attempts, 1);
      expect(statuses(queue), ['1:canceled']);
    });
  });

  test('retries a handler that throws right away many times', () async {
    final queue = QueueIt<int>(
      retries: 20000,
      itemHandler: (item) => throw const FormatException('bad'),
    );
    addTearDown(queue.dispose);
    queue.onUpdate.listen((snapshot) {});
    final finished = queue.waitFor(queue.add(1));

    queue.start();
    final item = await finished.timeout(const Duration(seconds: 30));

    expect(item.status, QueueItemStatus.failed);
    expect(item.retryCount, 20000);
    await queue.running;
  });

  test('lets waitFor called as an attempt fails wait for the retry', () async {
    final queue = QueueIt<int>(
      retries: 1,
      itemHandler: (item) {
        if (item.retryCount == 0) throw Exception('flaky');
      },
    );
    addTearDown(queue.dispose);
    final waited = <Future<QueueItem<int>>>[];
    queue.onUpdate.listen((snapshot) {
      final item = snapshot.eventItem;
      if (item?.status == QueueItemStatus.failed) {
        waited.add(queue.waitFor(item!.id));
      }
    });

    queue
      ..add(1)
      ..start();
    await queue.running;

    final item = await waited.single;
    expect(item.status, QueueItemStatus.completed);
    expect(item.retryCount, 1);
  });

  test('lets a listener cancel the retry as an attempt fails', () async {
    var attempts = 0;
    final queue = QueueIt<int>(
      retries: 2,
      itemHandler: (item) {
        attempts++;
        throw Exception('failed');
      },
    );
    addTearDown(queue.dispose);
    final events = recordEvents(queue);
    final canceled = <bool>[];
    queue.onUpdate.listen((snapshot) {
      final item = snapshot.eventItem;
      if (item?.status == QueueItemStatus.failed) {
        canceled.add(queue.cancel(item!));
      }
    });
    final finished = queue.waitFor(queue.add(1));

    queue.start();

    expect((await finished).status, QueueItemStatus.canceled);
    await queue.running;
    expect(canceled, [true]);
    expect(attempts, 1);
    expect(events, [
      'itemAdded:1:pending',
      'startedQueue',
      'startedProcessing',
      'itemStatusUpdated:1:processing',
      'itemStatusUpdated:1:failed',
      'itemStatusUpdated:1:canceled',
      'stoppedProcessing',
      'stoppedQueue',
    ]);
  });

  test("doesn't cancel an item whose last attempt failed", () async {
    final queue = QueueIt<int>(
      retries: 1,
      itemHandler: (item) => throw Exception('failed'),
    );
    addTearDown(queue.dispose);
    final canceled = <bool>[];
    queue.onUpdate.listen((snapshot) {
      final item = snapshot.eventItem;
      if (item?.status == QueueItemStatus.failed && item!.retryCount == 1) {
        canceled.add(queue.cancel(item));
      }
    });

    queue
      ..add(1)
      ..start();
    await queue.running;

    expect(canceled, [false]);
    expect(statuses(queue), ['1:failed']);
  });

  test('reports an error thrown by retryIf or retryDelay, and fails the item',
      () async {
    for (final callback in ['retryIf', 'retryDelay']) {
      final errors = <Object>[];
      late QueueItem<int> finished;
      await runZonedGuarded(() async {
        final queue = QueueIt<int>(
          retries: 1,
          retryIf: callback == 'retryIf'
              ? (item, error) => throw StateError(callback)
              : null,
          retryDelay: callback == 'retryDelay'
              ? (item, retry) => throw StateError(callback)
              : null,
          itemHandler: (item) => throw Exception('failed'),
        );
        final done = queue.waitFor(queue.add(1));
        queue.start();
        finished = await done;
        await queue.running;
        queue.dispose();
      }, (error, stackTrace) => errors.add(error));

      expect(finished.status, QueueItemStatus.failed, reason: callback);
      expect(finished.retryCount, 0, reason: callback);
      expect(errors, [isA<StateError>()], reason: callback);
    }
  });

  test('leaves no retry timer when a listener disposes the queue', () async {
    // Disposed as the attempt fails, or as its retry is queued.
    for (final status in [QueueItemStatus.failed, QueueItemStatus.pending]) {
      final timers = <Timer>[];
      await runZoned(
        () async {
          final queue = QueueIt<int>(
            retries: 1,
            retryDelay: (item, retry) => const Duration(hours: 1),
            itemHandler: (item) => throw Exception('failed'),
          );
          queue.onUpdate.listen((snapshot) {
            final item = snapshot.eventItem;
            if (item?.status == status && item?.startedProcessingAt != null) {
              queue.dispose();
            }
          });
          queue
            ..add(1)
            ..start();
          await queue.running;
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );

      expect(timers.where((timer) => timer.isActive), isEmpty,
          reason: 'disposed in the ${status.name} event');
      for (final timer in timers) {
        timer.cancel();
      }
    }
  });

  test('drops waiting retries on removeAll and dispose', () async {
    var attempts = 0;
    QueueIt<int> failing() => QueueIt<int>(
          retries: 1,
          retryDelay: (item, retry) => const Duration(milliseconds: 20),
          itemHandler: (item) {
            attempts++;
            throw Exception('failed');
          },
        );
    final cleared = failing()
      ..add(1)
      ..start();
    addTearDown(cleared.dispose);
    final disposed = failing()
      ..add(2)
      ..start();
    await wait(5);

    cleared.removeAll();
    disposed.dispose();
    await cleared.running;
    await wait(40);

    expect(attempts, 2);
  });

  test('lets a listener remove an item that failed', () async {
    final queue = QueueIt<int>(
      retries: 2,
      itemHandler: (item) => throw Exception('failed'),
    );
    addTearDown(queue.dispose);
    queue.onUpdate.listen((snapshot) {
      if (snapshot.eventItem?.status == QueueItemStatus.failed) {
        queue.remove(snapshot.eventItem!);
      }
    });
    queue
      ..add(1)
      ..start();
    await queue.running;

    expect(queue.items(), isEmpty);
  });

  group('during a failure that will be retried', () {
    test('a listener cancels the item once', () async {
      final queue = QueueIt<int>(
        retries: 1,
        itemHandler: (item) => throw Exception('failed'),
      );
      addTearDown(queue.dispose);
      final events = recordEvents(queue);
      final results = <bool>[];
      // Two listeners that each cancel an item when it fails, and one that
      // cancels it whenever it hears of it after that.
      for (var i = 0; i < 2; i++) {
        queue.onUpdate.listen((snapshot) {
          final item = snapshot.eventItem;
          if (item?.status == QueueItemStatus.failed) {
            results.add(queue.cancel(item!));
          }
        });
      }
      var calls = 0;
      queue.onUpdate.listen((snapshot) {
        final item = snapshot.eventItem;
        if (item != null && item.failedAt != null && calls < 100) {
          calls++;
          queue.cancel(item);
        }
      });

      queue
        ..add(1)
        ..start();
      await queue.running;

      expect(results, [true, false]);
      expect(calls, lessThan(100));
      expect(
          events.where((event) => event.endsWith(':canceled')), hasLength(1));
    });

    test(
        'an item added once a listener removed the failing one starts a '
        'new batch', () async {
      final queue = QueueIt<int>(
        retries: 1,
        itemHandler: (item) {
          if (item.data == 1) throw Exception('failed');
        },
      );
      addTearDown(queue.dispose);
      queue.onUpdate.listen((snapshot) {
        final item = snapshot.eventItem;
        if (item?.data == 1 && item?.status == QueueItemStatus.failed) {
          queue
            ..remove(item!)
            ..add(2);
        }
      });
      queue.add(1);
      final first = queue.currentBatchId;

      queue.start();
      await queue.running;

      expect(statuses(queue), ['2:completed']);
      expect(queue.items().single.batchId, isNot(first));
    });

    test('retryIf and retryDelay can cancel or remove the item', () async {
      for (final callback in ['retryIf', 'retryDelay']) {
        for (final remove in [false, true]) {
          late QueueIt<int> queue;
          var attempts = 0;
          void call() {
            remove ? queue.removeById('a') : queue.cancelById('a');
          }

          queue = QueueIt<int>(
            retries: 1,
            retryIf: callback == 'retryIf'
                ? (item, error) {
                    call();
                    return true;
                  }
                : null,
            retryDelay: callback == 'retryDelay'
                ? (item, retry) {
                    call();
                    return Duration.zero;
                  }
                : null,
            itemHandler: (item) {
              attempts++;
              throw Exception('failed');
            },
          );
          final finished = queue.waitFor(queue.add(1, id: 'a'));

          queue.start();
          await queue.running.timeout(const Duration(seconds: 1));

          final reason = '${remove ? 'removed' : 'canceled'} by $callback';
          expect(attempts, 1, reason: reason);
          expect((await finished).status,
              remove ? QueueItemStatus.removed : QueueItemStatus.canceled,
              reason: reason);
          expect(statuses(queue), remove ? isEmpty : ['1:canceled'],
              reason: reason);
          queue.dispose();
        }
      }
    });

    test("retryDelay isn't called once retryIf has ended the item", () async {
      for (final action in ['cancel', 'remove', 'dispose']) {
        late QueueIt<int> queue;
        final delays = <int>[];
        queue = QueueIt<int>(
          retries: 1,
          retryIf: (item, error) {
            switch (action) {
              case 'cancel':
                queue.cancelById('a');
              case 'remove':
                queue.removeById('a');
              case 'dispose':
                queue.dispose();
            }
            return true;
          },
          retryDelay: (item, retry) {
            delays.add(retry);
            return Duration.zero;
          },
          itemHandler: (item) => throw Exception('failed'),
        );

        queue
          ..add(1, id: 'a')
          ..start();
        await queue.running;
        await wait();

        expect(delays, isEmpty, reason: action);
        queue.dispose();
      }
    });

    test('an item added by retryIf joins the batch', () async {
      late QueueIt<int> queue;
      queue = QueueIt<int>(
        retries: 1,
        retryIf: (item, error) {
          if (queue.items().length == 1) queue.add(2);
          return true;
        },
        itemHandler: (item) {
          if (item.data == 1 && item.retryCount == 0) {
            throw Exception('flaky');
          }
        },
      );
      addTearDown(queue.dispose);

      queue
        ..add(1)
        ..start();
      await queue.running;

      expect(statuses(queue), ['1:completed', '2:completed']);
      expect(queue.items().map((item) => item.batchId).toSet(),
          {queue.currentBatchId});
    });

    test('a listener that disposes the queue leaves the item pending',
        () async {
      final queue = QueueIt<int>(
        retries: 2,
        itemHandler: (item) => throw Exception('failed'),
      );
      final id = queue.add(1);
      final before = queue.waitFor(id);
      queue.onUpdate.listen((snapshot) {
        if (snapshot.eventItem?.status == QueueItemStatus.failed) {
          queue.dispose();
        }
      });

      queue.start();

      await expectLater(before, throwsStateError);
      expect(statuses(queue), ['1:pending']);
      await expectLater(queue.waitFor(id), throwsStateError);
    });

    test(
        'retryIf or retryDelay that disposes the queue leaves the item as it is',
        () async {
      for (final callback in ['retryIf', 'retryDelay']) {
        late QueueIt<int> queue;
        queue = QueueIt<int>(
          retries: 1,
          retryIf: callback == 'retryIf'
              ? (item, error) {
                  queue.dispose();
                  return true;
                }
              : null,
          retryDelay: callback == 'retryDelay'
              ? (item, retry) {
                  queue.dispose();
                  return Duration.zero;
                }
              : null,
          itemHandler: (item) => throw Exception('failed'),
        );

        queue
          ..add(1)
          ..start();
        await wait(5);

        expect(statuses(queue), ['1:processing'], reason: callback);
        expect(queue.items().single.error, isNull, reason: callback);
      }
    });
  });
}
