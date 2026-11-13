import 'package:queue_it/queue_it.dart';

/// Processes five downloads two at a time. The third fails twice before it
/// works, and the program waits for it with `waitFor`.
Future<void> main() async {
  final queue = QueueIt<String>(
    parallel: 2,
    retries: 3,
    retryDelay: (item, retry) => Duration(milliseconds: 200 * retry),
    useFriendlyIds: true,
    itemHandler: (item) async {
      // Fake processing time.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (item.data == 'file-3.zip' && item.retryCount < 2) {
        throw Exception('connection reset');
      }
    },
  )..onUpdate.listen((snapshot) {
      if (snapshot.eventItem != null) {
        print(snapshot.eventItem!.summaryTableLine);
      } else {
        print(snapshot.event.name);
      }
    });

  final ids = [
    for (var i = 1; i <= 5; i++) queue.add('file-$i.zip'),
  ];

  /// Start processing the queue.
  queue.start();

  final third = await queue.waitFor(ids[2]);
  print('file-3.zip is ${third.status.name} after ${third.retryCount} '
      'retries; the last error was: ${third.error}');

  await queue.running;
  print(queue.items().summary);
  queue.dispose();
}
