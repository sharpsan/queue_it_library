import 'package:queue_it/queue_it.dart';
import 'package:test/test.dart';

/// This test checks that each item reached the maximum number of retries.
void main() {
  /// tests that the items get retried when they fail
  test('Retries', () async {
    final queue = QueueIt<int>(
      parallel: 2,
      retries: 3,
      itemHandler: (item) async {
        throw Exception('Failed');
      },
    )
      ..onUpdate.listen((snapshot) {
        if (snapshot.eventItem != null) {
          print(snapshot.eventItem!.summaryTableLine);
        } else {
          print(snapshot.event.name);
        }

        if (snapshot.event == QueueEvent.stoppedQueue) {
          print(snapshot.items.summary);

          /// check the number of times we retried the items
          for (final item in snapshot.items) {
            expect(item.retryCount, snapshot.retries);
          }
        }
      })
      ..start(stopAutomatically: true);

    /// add items to the queue
    queue.add(1);
    queue.add(2);
    queue.add(3);

    await queue.running;
  });
}
