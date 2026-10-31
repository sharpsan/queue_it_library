import 'package:flutter/widgets.dart';
import 'package:flutter_queue_it/flutter_queue_it.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests pin the QueueItWidget behavior that the README and API docs describe.
void main() {
  late QueueIt<String> queue;
  late List<QueueSnapshot<String>?> builds;

  setUp(() {
    queue = QueueIt<String>(itemHandler: (item) {});
    builds = [];
  });

  tearDown(() => queue.dispose());

  /// Records every snapshot the builder receives.
  Widget recorder(QueueIt<String> queue, List<QueueSnapshot<String>?> builds) {
    return QueueItWidget<String>(
      queue: queue,
      builder: (context, snapshot) {
        builds.add(snapshot);
        return const SizedBox();
      },
    );
  }

  testWidgets('builds with a null snapshot before the first event',
      (tester) async {
    queue.add('added before the widget');
    await tester.pumpWidget(recorder(queue, builds));

    expect(builds, [null]);
    expect(queue.items(), hasLength(1));
  });

  testWidgets('rebuilds with the latest snapshot when the queue updates',
      (tester) async {
    await tester.pumpWidget(recorder(queue, builds));

    queue.add('a');
    await tester.pump();

    expect(builds, hasLength(2));
    final snapshot = builds.last!;
    expect(snapshot.event, QueueEvent.itemAdded);
    expect(snapshot.eventItem!.data, 'a');
    expect(snapshot.items.map((item) => item.data), ['a']);
  });

  testWidgets('rebuilds once per frame however many events arrive',
      (tester) async {
    await tester.pumpWidget(recorder(queue, builds));

    queue
      ..add('a')
      ..add('b')
      ..add('c');
    await tester.pump();

    expect(builds, hasLength(2));
    expect(builds.last!.eventItem!.data, 'c');
    expect(builds.last!.items, hasLength(3));
  });

  testWidgets('follows items through processing until the queue stops',
      (tester) async {
    await tester.pumpWidget(recorder(queue, builds));

    queue
      ..add('a')
      ..add('b')
      ..start();
    await tester.pumpAndSettle();

    final snapshot = builds.last!;
    expect(snapshot.event, QueueEvent.stoppedQueue);
    expect(snapshot.isStarted, isFalse);
    expect(snapshot.items.completed, hasLength(2));
  });

  testWidgets('listens to the new queue when the queue changes',
      (tester) async {
    final other = QueueIt<String>(itemHandler: (item) {});
    addTearDown(other.dispose);
    await tester.pumpWidget(recorder(queue, builds));
    queue.add('from the first queue');
    await tester.pump();

    await tester.pumpWidget(recorder(other, builds));
    final buildsAfterSwap = builds.length;
    // Until the new queue emits, the builder keeps the old queue's snapshot.
    expect(builds.last!.eventItem!.data, 'from the first queue');

    queue.add('ignored');
    await tester.pump();
    expect(builds, hasLength(buildsAfterSwap));

    other.add('from the second queue');
    await tester.pump();
    expect(builds.last!.eventItem!.data, 'from the second queue');
  });

  testWidgets('lets several widgets listen to one queue', (tester) async {
    final otherBuilds = <QueueSnapshot<String>?>[];
    await tester.pumpWidget(Column(
      children: [recorder(queue, builds), recorder(queue, otherBuilds)],
    ));

    queue.add('a');
    await tester.pump();

    expect(builds.last!.eventItem!.data, 'a');
    expect(otherBuilds.last!.eventItem!.data, 'a');
  });

  testWidgets('rebuilds only for the events buildWhen allows', (tester) async {
    await tester.pumpWidget(QueueItWidget<String>(
      queue: queue,
      buildWhen: (snapshot) => snapshot.event == QueueEvent.itemAdded,
      builder: (context, snapshot) {
        builds.add(snapshot);
        return const SizedBox();
      },
    ));

    queue
      ..add('a')
      ..start();
    await tester.pumpAndSettle();

    expect(builds, hasLength(2));
    expect(builds.last!.event, QueueEvent.itemAdded);
    expect(queue.items().completed, hasLength(1));
  });

  testWidgets('uses the buildWhen of the latest widget', (tester) async {
    Widget build(bool rebuild) => QueueItWidget<String>(
          queue: queue,
          buildWhen: (snapshot) => rebuild,
          builder: (context, snapshot) {
            builds.add(snapshot);
            return const SizedBox();
          },
        );
    await tester.pumpWidget(build(false));
    queue.add('skipped');
    await tester.pump();
    expect(builds, [null]);

    await tester.pumpWidget(build(true));
    queue.add('built');
    await tester.pump();
    expect(builds.last!.eventItem!.data, 'built');
  });

  testWidgets('leaves the queue usable after the widget is removed',
      (tester) async {
    await tester.pumpWidget(recorder(queue, builds));
    await tester.pumpWidget(const SizedBox());

    queue
      ..add('a')
      ..start();
    await tester.pumpAndSettle();

    expect(queue.items().completed, hasLength(1));
  });
}
