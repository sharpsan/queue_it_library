import 'package:queue_it/queue_it.dart';

void main() {
  final queue = QueueIt<int>(
      parallel: 3,
      retries: 3,
      useFriendlyIds: true,
      itemHandler: (item) async {
        print('Handling item: ${item.id}');

        /// Fake processing time
        await Future.delayed(Duration(seconds: 1));
      })
    ..onUpdate.listen((snapshot) {
      if (snapshot.eventItem != null) {
        print(snapshot.eventItem!.summaryTableLine);
      } else {
        print(snapshot.event.name);
      }
    });

  /// Add some items to the queue
  queue.add(1);
  queue.add(2);
  queue.add(3);

  /// start processing the queue
  queue.start();

  /// You can continue adding more items to the queue after it starts processing
  queue.add(4);
  queue.add(5);
}
