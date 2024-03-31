import 'package:queue_it/queue_it.dart';
import 'package:test/test.dart';

/// This test checks that the queue emitted events in the correct order.
/// The order of events should be:
void main() async {
  test('Order of operations test', () async {
    final queue = QueueIt<int>(
      parallel: 2,
      retries: 3,
      itemHandler: (item) async {
        await Future.delayed(Duration(milliseconds: 1));
      },
    )
      ..onUpdate.listen((snapshot) {
        if (snapshot.eventItem != null) {
          print(snapshot.eventItem!.summaryTableLine);
        } else {
          print(snapshot.event.name);
        }

        if (snapshot.event == QueueEvent.stoppedQueue) {
          final datesInOrder = [
            snapshot.startedAt!,
            snapshot.startedProcessingAt!,
            for (final item in snapshot.items) ...[
              item.startedProcessingAt!,
            ],
            snapshot.stoppedProcessingAt!,
            snapshot.stoppedAt!,
          ];
          datesInOrder;

          /// test that dates are in ascending order
          for (var i = 0; i < datesInOrder.length - 1; i++) {
            /// if this is the last item, return
            if (i == datesInOrder.length - 1) {
              return;
            }
            final date = datesInOrder[i];
            final nextDate = datesInOrder[i + 1];
            expect(
              date.isBefore(nextDate) || date.isAtSameMomentAs(nextDate),
              true,
            );
          }
        }
      })
      ..start(stopAutomatically: true);

    /// add items to the queue
    queue.add(1);
    queue.add(2);
    queue.add(3);
    queue.add(4);
    queue.add(5);
    queue.add(6);
    queue.add(7);

    await queue.running;
  });
}
