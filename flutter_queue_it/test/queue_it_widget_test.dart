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
    queue.start(stopAutomatically: false);
    await tester.pumpWidget(recorder(queue, builds));
    await tester.pumpWidget(const SizedBox());

    // The queue isn't the widget's to stop.
    expect(queue.isStarted, isTrue);
    queue.add('a');
    await tester.pumpAndSettle();

    expect(queue.items().completed, hasLength(1));
  });

  testWidgets(
      'does not rebuild for a change made while building the frame that '
      'removes it', (tester) async {
    await tester.pumpWidget(Column(children: [recorder(queue, builds)]));

    // The new widget adds an item as it's built, in the frame that takes the
    // QueueItWidget out of the tree.
    await tester.pumpWidget(Column(children: [
      _Lifecycle(onInit: () => queue.add('from initState')),
    ]));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(queue.items(), hasLength(1));
    expect(builds, [null]);
  });

  testWidgets(
      'does not rebuild for a change its child makes from dispose in the '
      'frame that removes it', (tester) async {
    final id = queue.add('a');
    await tester.pumpWidget(QueueItWidget<String>(
      queue: queue,
      builder: (context, snapshot) =>
          _Lifecycle(onDispose: () => queue.cancelById(id)),
    ));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(queue.items().single.status, QueueItemStatus.canceled);
  });

  testWidgets(
      'does not rebuild for a change made in a build outside a frame when it '
      'is removed before the frame', (tester) async {
    await tester.pumpWidget(recorder(queue, builds));
    final element = tester.element(find.byType(QueueItWidget<String>));
    tester.binding.buildOwner!.buildScope(element, () => queue.add('a'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(builds, [null]);
  });

  testWidgets('rebuilds after the frame for changes made while it builds',
      (tester) async {
    // A child that adds an item as it's built, on the first build and on a
    // later one.
    Widget build({required bool withChild}) => QueueItWidget<String>(
          queue: queue,
          builder: (context, snapshot) {
            builds.add(snapshot);
            return withChild
                ? _Lifecycle(onInit: () => queue.add('from initState'))
                : const SizedBox();
          },
        );
    await tester.pumpWidget(build(withChild: true));
    await tester.pump();
    expect(builds.last!.eventItem!.data, 'from initState');

    await tester.pumpWidget(build(withChild: false));
    await tester.pumpWidget(build(withChild: true));
    await tester.pump();
    expect(queue.items(), hasLength(2));
    expect(builds.last!.items, hasLength(2));
    expect(builds.last!.eventItem!.id, queue.items().last.id);

    // And it keeps rebuilding for later changes.
    queue.add('later');
    await tester.pump();
    expect(builds.last!.eventItem!.data, 'later');
  });

  testWidgets('lets its own builder change the queue', (tester) async {
    final counts = <int>[];
    // In the app's first build (outside a frame), and in a later frame.
    await tester.pumpWidget(QueueItWidget<String>(
      queue: queue,
      builder: (context, snapshot) {
        final count = queue.items().length;
        counts.add(count);
        if (count < 2) queue.add('item $count');
        return const SizedBox();
      },
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(counts.last, 2);
  });

  testWidgets(
      'rebuilds after the frame for changes made in a build outside '
      'a frame', (tester) async {
    // Flutter builds the app's first widgets that way, in runApp.
    final shown = ValueNotifier(false);
    await tester.pumpWidget(Column(children: [
      recorder(queue, builds),
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, show, child) => show
            ? _Lifecycle(onInit: () => queue.add('from initState'))
            : const SizedBox(),
      ),
    ]));
    shown.value = true;
    final element = tester.element(find.byType(ValueListenableBuilder<bool>));

    tester.binding.buildOwner!.buildScope(element);

    expect(tester.takeException(), isNull);
    expect(queue.items(), hasLength(1));
    // The deferred rebuild runs after the next frame, in the one after it.
    await tester.pump();
    await tester.pump();
    expect(builds.last!.eventItem!.data, 'from initState');
  });

  testWidgets('schedules a frame for a change made in a build outside a frame',
      (tester) async {
    await tester.pumpWidget(recorder(queue, builds));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final element = tester.element(find.byType(QueueItWidget<String>));

    tester.binding.buildOwner!.buildScope(element, () => queue.add('a'));

    // Nothing else asked for a frame, and the rebuild waits for one.
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    await tester.pump();
    expect(builds.last!.eventItem!.data, 'a');
  });

  testWidgets(
      'rebuilds after the frame for changes made by a widget it '
      'disposes', (tester) async {
    final id = queue.add('a');
    Widget build({required bool withTile}) => Column(children: [
          recorder(queue, builds),
          if (withTile) _Lifecycle(onDispose: () => queue.cancelById(id)),
        ]);
    await tester.pumpWidget(build(withTile: true));

    await tester.pumpWidget(build(withTile: false));
    await tester.pump();

    expect(builds.last!.eventItem!.status, QueueItemStatus.canceled);
  });

  testWidgets('rebuilds after the frame for changes made during layout',
      (tester) async {
    await tester.pumpWidget(Column(children: [
      recorder(queue, builds),
      LayoutBuilder(builder: (context, constraints) {
        if (queue.items().isEmpty) queue.add('from layout');
        return const SizedBox();
      }),
    ]));
    await tester.pump();

    expect(builds.last!.eventItem!.data, 'from layout');
  });
}

/// Calls [onInit] from initState and [onDispose] from dispose, like a widget
/// that adds its work to a queue when it appears, or cancels it when it goes.
class _Lifecycle extends StatefulWidget {
  const _Lifecycle({this.onInit, this.onDispose});

  final VoidCallback? onInit;
  final VoidCallback? onDispose;

  @override
  State<_Lifecycle> createState() => _LifecycleState();
}

class _LifecycleState extends State<_Lifecycle> {
  @override
  void initState() {
    super.initState();
    widget.onInit?.call();
  }

  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
