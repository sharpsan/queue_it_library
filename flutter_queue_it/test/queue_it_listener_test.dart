import 'package:flutter/widgets.dart';
import 'package:flutter_queue_it/flutter_queue_it.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late QueueIt<String> queue;
  late List<String> events;

  setUp(() {
    queue = QueueIt<String>(itemHandler: (item) {});
    events = [];
  });

  tearDown(() => queue.dispose());

  Widget listener(QueueIt<String> queue, {Widget child = const SizedBox()}) {
    return QueueItListener<String>(
      queue: queue,
      listener: (context, snapshot) {
        final item = snapshot.eventItem;
        events.add(item == null
            ? snapshot.event.name
            : '${snapshot.event.name}:${item.data}:${item.status.name}');
      },
      child: child,
    );
  }

  testWidgets('calls the listener for every event, in order', (tester) async {
    await tester.pumpWidget(listener(queue));

    queue
      ..add('a')
      ..add('b');
    expect(events, ['itemAdded:a:pending', 'itemAdded:b:pending']);

    queue.start();
    await tester.pumpAndSettle();
    expect(events, [
      'itemAdded:a:pending',
      'itemAdded:b:pending',
      'startedQueue',
      'startedProcessing',
      'itemStatusUpdated:a:processing',
      'itemStatusUpdated:a:completed',
      'itemStatusUpdated:b:processing',
      'itemStatusUpdated:b:completed',
      'stoppedProcessing',
      'stoppedQueue',
    ]);
  });

  testWidgets('builds its child without rebuilding it', (tester) async {
    var builds = 0;
    await tester.pumpWidget(listener(
      queue,
      child: Builder(builder: (context) {
        builds++;
        return const SizedBox();
      }),
    ));

    queue.add('a');
    await tester.pump();

    expect(builds, 1);
    expect(events, hasLength(1));
  });

  testWidgets('lets the listener call the queue', (tester) async {
    await tester.pumpWidget(QueueItListener<String>(
      queue: queue,
      listener: (context, snapshot) {
        final item = snapshot.eventItem;
        if (item != null &&
            item.status == QueueItemStatus.completed &&
            item.data == 'a') {
          queue.add('follow-up');
        }
      },
      child: const SizedBox(),
    ));

    queue
      ..add('a')
      ..start(stopAutomatically: false);
    await tester.pumpAndSettle();

    expect(queue.items().map((item) => '${item.data}:${item.status.name}'),
        ['a:completed', 'follow-up:completed']);
    queue.stop();
  });

  testWidgets('listens to the new queue when the queue changes',
      (tester) async {
    final other = QueueIt<String>(itemHandler: (item) {});
    addTearDown(other.dispose);
    await tester.pumpWidget(listener(queue));

    await tester.pumpWidget(listener(other));
    queue.add('ignored');
    other.add('heard');

    expect(events, ['itemAdded:heard:pending']);
  });

  testWidgets('stops listening when removed', (tester) async {
    await tester.pumpWidget(listener(queue));
    await tester.pumpWidget(const SizedBox());

    queue.add('a');

    expect(events, isEmpty);
  });
}
