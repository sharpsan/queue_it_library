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

  test('fails an item without retrying when retryIf says no', () async {
    final errors = <Object>[];
    final queue = QueueIt<int>(
      retries: 3,
      retryIf: (error) {
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

  group('retryDelay', () {
    test('waits before each retry', () async {
      final retries = <int>[];
      final attempts = <DateTime>[];
      final queue = QueueIt<int>(
        retries: 2,
        retryDelay: (retry) {
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
        retryDelay: (retry) => const Duration(milliseconds: 30),
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
        retryDelay: (retry) => const Duration(milliseconds: 20),
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
        retryDelay: (retry) => const Duration(hours: 1),
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

  test('drops waiting retries on removeAll and dispose', () async {
    var attempts = 0;
    QueueIt<int> failing() => QueueIt<int>(
          retries: 1,
          retryDelay: (retry) => const Duration(milliseconds: 20),
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
}
