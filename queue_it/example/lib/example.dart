import 'package:queue_it/queue_it.dart';

void main() {
  final queue = QueueIt<int>(
      concurrentOperations: 1,
      retryLimit: 3,
      itemHandler: (item) async {
        print('Handling item: ${item.id}');

        /// Fake processing time
        await Future.delayed(Duration(seconds: 1));
      })
    ..onUpdate.listen((snapshot) {
      print('Queue updated: ${snapshot.event.name}');
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
