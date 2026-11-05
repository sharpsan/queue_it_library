import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:queue_it/queue_it.dart';

/// Run with `dart run benchmark/queue_it_benchmark.dart`.
void main() async {
  AddBenchmark().report();
  await ProcessBenchmark(1000).report();
  await ProcessBenchmark(10000).report();
}

/// Adds 100 items to a queue with a listener.
class AddBenchmark extends BenchmarkBase {
  AddBenchmark() : super('QueueIt.add');

  QueueIt<int>? queue;

  @override
  void run() {
    for (int i = 0; i < 100; i++) {
      queue?.add(i);
    }
  }

  @override
  void setup() {
    queue = QueueIt(itemHandler: (item) {})
      // Adds a subscriber so that snapshot events are sent.
      ..onUpdate.listen((event) {});
  }

  @override
  void teardown() {
    queue?.dispose();
  }
}

/// Processes [count] items with a handler that does nothing, four at a time.
class ProcessBenchmark extends AsyncBenchmarkBase {
  ProcessBenchmark(this.count) : super('QueueIt processing $count items');

  final int count;

  @override
  Future<void> run() async {
    final queue = QueueIt<int>(parallel: 4, itemHandler: (item) {})
      ..onUpdate.listen((event) {});
    for (var i = 0; i < count; i++) {
      queue.add(i);
    }
    queue.start();
    await queue.running;
    queue.dispose();
  }
}
