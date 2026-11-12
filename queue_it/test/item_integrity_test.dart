import 'package:queue_it/src/models/queue_item.dart';
import 'package:queue_it/src/models/queue_item_status.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() async {
  test('Item Integrity', () {
    final queueItem = QueueItem(
      id: '1',
      batchId: 'a',
      data: 1,
      status: QueueItemStatus.pending,
    );

    expect(queueItem.queuedAt, isNotNull);
    expect(queueItem.retryCount, 0);

    /// test all props
    expect(queueItem.id, '1');
    expect(queueItem.batchId, 'a');
    expect(queueItem.data, 1);
    expect(queueItem.status, QueueItemStatus.pending);

    /// test updating to each status

    /// pending -> processing
    expect(queueItem.startedProcessingAt, isNull);
    queueItem.updateStatus(QueueItemStatus.processing);
    expect(queueItem.status, QueueItemStatus.processing);
    expect(queueItem.startedProcessingAt, isNotNull);

    /// processing -> completed
    expect(queueItem.completedAt, isNull);
    queueItem.updateStatus(QueueItemStatus.completed);
    expect(queueItem.status, QueueItemStatus.completed);
    expect(queueItem.completedAt, isNotNull);

    /// completed -> failed
    expect(queueItem.failedAt, isNull);
    queueItem.updateStatus(QueueItemStatus.failed);
    expect(queueItem.status, QueueItemStatus.failed);
    expect(queueItem.failedAt, isNotNull);

    /// failed -> canceled
    expect(queueItem.canceledAt, isNull);
    queueItem.updateStatus(QueueItemStatus.canceled);
    expect(queueItem.status, QueueItemStatus.canceled);
    expect(queueItem.canceledAt, isNotNull);

    /// canceled -> removed
    expect(queueItem.removedAt, isNull);
    queueItem.updateStatus(QueueItemStatus.removed);
    expect(queueItem.status, QueueItemStatus.removed);
    expect(queueItem.removedAt, isNotNull);

    /// removed -> pending
    expect(queueItem.queuedAt, isNotNull);
    queueItem.updateStatus(QueueItemStatus.pending);
    expect(queueItem.status, QueueItemStatus.pending);
    expect(queueItem.queuedAt, isNotNull);
    expect(queueItem.retryCount, 1);

    /// test changing to same status - should have no effect
    queueItem.updateStatus(QueueItemStatus.pending);
    expect(queueItem.retryCount, 1);
  });

  test('copyWith replaces only the given fields', () {
    final error = StateError('boom');
    final stackTrace = StackTrace.current;
    final item = QueueItem(
      batchId: 'a',
      data: 1,
      status: QueueItemStatus.failed,
    )..nextStatus = QueueItemStatus.pending;

    /// The constructor records when the item got to its status
    expect(item.failedAt, isNotNull);

    final failed = item.copyWith(error: error, stackTrace: stackTrace);
    expect(failed.id, item.id);
    expect(failed.status, QueueItemStatus.failed);
    expect(failed.failedAt, item.failedAt);
    expect(failed.error, same(error));
    expect(failed.stackTrace, same(stackTrace));
    expect(failed.nextStatus, isNull);

    /// A new status keeps the times the item reached each status
    final completed = failed.copyWith(status: QueueItemStatus.completed);
    expect(completed.status, QueueItemStatus.completed);
    expect(completed.completedAt, isNull);
    expect(completed.failedAt, item.failedAt);
    expect(completed.error, same(error));
    expect(completed.stackTrace, same(stackTrace));
  });

  test('copyWith replaces each field it is given', () {
    final item = QueueItem(
      id: 'a',
      batchId: 'batch',
      data: 1,
      status: QueueItemStatus.pending,
    );
    DateTime at(int day) => DateTime(2000, 1, day);

    final copy = item.copyWith(
      id: 'b',
      data: 2,
      batchId: 'other',
      retryCount: 3,
      queuedAt: at(1),
      startedProcessingAt: at(2),
      completedAt: at(3),
      failedAt: at(4),
      canceledAt: at(5),
      removedAt: at(6),
    );

    expect(copy.id, 'b');
    expect(copy.data, 2);
    expect(copy.batchId, 'other');
    expect(copy.retryCount, 3);
    expect(copy.queuedAt, at(1));
    expect(copy.startedProcessingAt, at(2));
    expect(copy.completedAt, at(3));
    expect(copy.failedAt, at(4));
    expect(copy.canceledAt, at(5));
    expect(copy.removedAt, at(6));
    expect(copy.status, QueueItemStatus.pending);

    /// And the item itself is unchanged
    expect(item.id, 'a');
    expect(item.data, 1);
    expect(item.retryCount, 0);
    expect(item.startedProcessingAt, isNull);
  });

  test('a copy keeps when the item reached each status', () async {
    final item = QueueItem(
      batchId: 'batch',
      data: 1,
      status: QueueItemStatus.pending,
    );
    for (final status in [
      QueueItemStatus.processing,
      QueueItemStatus.completed,
      QueueItemStatus.failed,
      QueueItemStatus.canceled,
      QueueItemStatus.removed,
    ]) {
      item.updateStatus(status);

      /// Long enough for the clock to move on, on Windows too
      await wait(20);

      final copy = item.copyWith();

      expect(copy.status, status);
      expect(copy.queuedAt, item.queuedAt, reason: status.name);
      expect(copy.startedProcessingAt, item.startedProcessingAt,
          reason: status.name);
      expect(copy.completedAt, item.completedAt, reason: status.name);
      expect(copy.failedAt, item.failedAt, reason: status.name);
      expect(copy.canceledAt, item.canceledAt, reason: status.name);
      expect(copy.removedAt, item.removedAt, reason: status.name);
      expect(copy.retryCount, 0);
    }
  });

  test('toString lists the fields, and the error only if there is one', () {
    final item = QueueItem(
      id: 'a',
      batchId: 'batch',
      data: 1,
      status: QueueItemStatus.pending,
    );

    expect(
      item.toString(),
      'Id: a\n'
      'Data: 1\n'
      'Batch Id: batch\n'
      'Status: QueueItemStatus.pending\n'
      'Queued At: ${item.queuedAt}\n'
      'Started Processing At: null\n'
      'Completed At: null\n'
      'Failed At: null\n'
      'Canceled At: null\n'
      'Removed At: null\n',
    );
    expect(item.copyWith(error: 'oops').toString(), endsWith('Error: oops\n'));
  });

  test('summaryTableLine lines up the status, data and id', () {
    final item = QueueItem(
      id: 'a',
      batchId: 'batch',
      data: 1,
      status: QueueItemStatus.pending,
    );

    expect(
      item.summaryTableLine,
      'pending         | 1                      | a                     ',
    );
  });
}
