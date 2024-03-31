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
    queueItem.status = QueueItemStatus.processing;
    expect(queueItem.status, QueueItemStatus.processing);
    expect(queueItem.startedProcessingAt, isNotNull);

    /// processing -> completed
    expect(queueItem.completedAt, isNull);
    queueItem.status = QueueItemStatus.completed;
    expect(queueItem.status, QueueItemStatus.completed);
    expect(queueItem.completedAt, isNotNull);

    /// completed -> failed
    expect(queueItem.failedAt, isNull);
    queueItem.status = QueueItemStatus.failed;
    expect(queueItem.status, QueueItemStatus.failed);
    expect(queueItem.failedAt, isNotNull);

    /// failed -> cancelled
    expect(queueItem.canceledAt, isNull);
    queueItem.status = QueueItemStatus.canceled;
    expect(queueItem.status, QueueItemStatus.canceled);
    expect(queueItem.canceledAt, isNotNull);

    /// cancelled -> removed
    expect(queueItem.removedAt, isNull);
    queueItem.status = QueueItemStatus.removed;
    expect(queueItem.status, QueueItemStatus.removed);
    expect(queueItem.removedAt, isNotNull);

    /// removed -> pending
    expect(queueItem.queuedAt, isNotNull);
    queueItem.status = QueueItemStatus.pending;
    expect(queueItem.status, QueueItemStatus.pending);
    expect(queueItem.queuedAt, isNotNull);
    expect(queueItem.retryCount, 1);

    /// test changing to same status - should have no effect
    queueItem.status = QueueItemStatus.pending;
    expect(queueItem.retryCount, 1);
  });
}
