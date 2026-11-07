import 'package:queue_it/src/models/queue_item.dart';
import 'package:queue_it/src/models/queue_item_status.dart';
import 'package:test/test.dart';

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
}
