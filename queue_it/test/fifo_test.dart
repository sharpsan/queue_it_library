import 'dart:async';
import 'dart:math' as math;

import 'package:queue_it/queue_it.dart';
import 'package:test/test.dart';

/// This test checks that items that are queued first are processed first.
void main() {
  /// tests that the items get processed in the order they were added
  test('FIFO', () async {
    QueueItem<int>? lastItemProcessed;
    final queue = QueueIt<int>(
      parallel: 3,
      itemHandler: (snapshot) async {
        final duration = Duration(
          milliseconds: (250 + (math.Random().nextInt(500))).toInt(),
        );

        await Future.delayed(duration);
      },
    )
      ..onUpdate.listen((snapshot) {
        if (snapshot.eventItem != null) {
          print(snapshot.eventItem!.summaryTableLine);
        } else {
          print(snapshot.event.name);
        }

        /// test that the items are processed in the order they were added
        if (snapshot.eventItem?.status == QueueItemStatus.processing) {
          /// if this is the first item, skip the test
          if (lastItemProcessed == null) {
            lastItemProcessed = snapshot.eventItem;
            return;
          }

          expect(snapshot.eventItem!.data, lastItemProcessed!.data + 1);

          lastItemProcessed = snapshot.eventItem;
        }
      })
      ..start(stopAutomatically: true);

    /// add items to the queue
    var i = 0;
    while (i < 10) {
      queue.add(i);
      i++;
    }

    await queue.running;
  });
}
