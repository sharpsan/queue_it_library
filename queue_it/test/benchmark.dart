import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:queue_it/queue_it.dart';

class QueueItBenchmark extends BenchmarkBase {
  QueueIt<int>? queue;

  QueueItBenchmark() : super('QueueIt');

  static void main() {
    QueueItBenchmark().report();
  }

  // The benchmark code.
  @override
  void run() {
    for (int i = 0; i < 100; i++) {
      queue?.add(i);
    }
  }

  @override
  void exercise() => run();

  // Not measured setup code executed prior to the benchmark runs.
  @override
  void setup() {
    queue = QueueIt(
      deepCopyItemsInSnapshot: false,
      itemHandler: (item) async {
        // Do nothing.
      },
    )..onUpdate.listen((event) {
        // Adds a subscriber so that snapshot events are sent.
      });
  }

  // Not measured teardown code executed after the benchmark runs.
  @override
  void teardown() {
    queue?.dispose();
  }
}

void main() {
  QueueItBenchmark.main();
}
