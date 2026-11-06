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

  testWidgets('stops calling the listener as it is removed', (tester) async {
    final id = queue.add('a');
    final errors = <Object>[];
    // The listener uses its context, which can't be used once the widget is
    // being removed.
    Widget build({required bool shown}) => Directionality(
          textDirection: TextDirection.ltr,
          child: shown
              ? QueueItListener<String>(
                  queue: queue,
                  listener: (context, snapshot) {
                    try {
                      Directionality.of(context);
                      events.add(snapshot.event.name);
                    } catch (error) {
                      errors.add(error);
                    }
                  },
                  // Cancels the item as it's removed, with the listener.
                  child: _Lifecycle(onDispose: () => queue.cancelById(id)),
                )
              : const SizedBox(),
        );
    await tester.pumpWidget(build(shown: true));

    await tester.pumpWidget(build(shown: false));

    expect(queue.items().single.status, QueueItemStatus.canceled);
    expect(events, isEmpty);
    expect(errors, isEmpty);
  });

  testWidgets('hears the events sent while it is moved', (tester) async {
    final key = GlobalKey();
    Widget build({required bool moved}) {
      final child = QueueItListener<String>(
        key: key,
        queue: queue,
        listener: (context, snapshot) {
          // The context is usable.
          Directionality.of(context);
          events.add('${snapshot.event.name}:${snapshot.eventItem?.data}');
        },
        child: const SizedBox(),
      );
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [
          // Built after the listener left its old place and before it joins
          // the new one.
          if (moved) _Lifecycle(onInit: () => queue.add('during')),
          moved
              ? Center(child: child)
              : Padding(
                  padding: EdgeInsets.zero,
                  child: child,
                ),
        ]),
      );
    }

    await tester.pumpWidget(build(moved: false));
    await tester.pumpWidget(build(moved: true));
    queue.add('after');

    expect(events, ['itemAdded:during', 'itemAdded:after']);
  });

  testWidgets('gives the events sent during a move to its new listener',
      (tester) async {
    final key = GlobalKey();
    Widget build({required bool moved}) {
      final child = QueueItListener<String>(
        key: key,
        queue: queue,
        listener: (context, snapshot) =>
            events.add('${moved ? 'new' : 'old'}:${snapshot.eventItem?.data}'),
        child: const SizedBox(),
      );
      return Column(children: [
        if (moved) _Lifecycle(onInit: () => queue.add('during')),
        moved
            ? Center(child: child)
            : Padding(padding: EdgeInsets.zero, child: child),
      ]);
    }

    await tester.pumpWidget(build(moved: false));
    await tester.pumpWidget(build(moved: true));
    queue.add('after');

    expect(events, ['new:during', 'new:after']);
  });

  testWidgets(
      'reports a listener that throws for an event sent during a '
      'move, and carries on', (tester) async {
    final key = GlobalKey();
    var disposes = 0;
    Widget child() => QueueItListener<String>(
          key: key,
          queue: queue,
          listener: (context, snapshot) {
            events.add('${snapshot.eventItem?.data}');
            if (snapshot.eventItem?.data == 'throws') {
              throw StateError('listener failed');
            }
          },
          child: _Lifecycle(onDispose: () => disposes++),
        );
    await tester.pumpWidget(Column(children: [
      Padding(padding: EdgeInsets.zero, child: child()),
    ]));

    await tester.pumpWidget(Column(children: [
      _Lifecycle(
          onInit: () => queue
            ..add('throws')
            ..add('next')),
      Center(child: child()),
    ]));

    expect(tester.takeException(), isStateError);
    queue.add('after');
    expect(events, ['throws', 'next', 'after']);
    expect(disposes, 0);

    await tester.pumpWidget(const SizedBox());
    expect(disposes, 1);
    queue.add('gone');
    expect(events, ['throws', 'next', 'after']);
  });

  testWidgets('keeps listening when moved with a GlobalKey', (tester) async {
    final key = GlobalKey();
    Widget build({required bool wrapped}) {
      final child = QueueItListener<String>(
        key: key,
        queue: queue,
        listener: (context, snapshot) => events.add(snapshot.event.name),
        child: const SizedBox(),
      );
      return wrapped ? Center(child: child) : child;
    }

    await tester.pumpWidget(build(wrapped: false));
    await tester.pumpWidget(build(wrapped: true));

    queue.add('a');

    expect(events, ['itemAdded']);
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
