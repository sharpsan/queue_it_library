

import 'package:easy_queue/src/models/queue_item.dart';
import 'package:easy_queue/src/models/queue_item_status.dart';
import 'package:test/test.dart';

main() {
  test('item status update test', () {
    final item = QueueItem<String>(
      data: 'test',
      status: QueueItemStatus.pending,
      batchId: 'batchId',
    );
    item.status = QueueItemStatus.completed;
    expect(item.status, QueueItemStatus.completed);
  });

  test('item copy test', () {
    final item = QueueItem<String>(
      data: 'test',
      status: QueueItemStatus.pending,
      batchId: 'batchId',
    );
    item.status = QueueItemStatus.completed;
    final itemCopy = item.copyWith();
    expect(itemCopy.data, item.data);
    expect(itemCopy.status, item.status);
    expect(itemCopy.batchId, item.batchId);
  });
}