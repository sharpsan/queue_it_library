import 'dart:async';

// The SnackBar tests need Material. flutter_queue_it supports Flutter
// versions from before the material_ui package, so they use the framework's.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
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

  testWidgets(
      'stops calling the listener when widgets removed before it change the '
      'queue', (tester) async {
    final above = queue.add('above');
    final before = queue.add('before');
    final errors = <Object>[];
    // Flutter deactivates the widgets above the listener, and the ones before
    // it, before the listener itself.
    Widget build({required bool shown}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [
            if (shown) _Lifecycle(onDeactivate: () => queue.cancelById(before)),
            if (shown)
              _Lifecycle(
                onDeactivate: () => queue.cancelById(above),
                child: QueueItListener<String>(
                  queue: queue,
                  listener: (context, snapshot) {
                    try {
                      Directionality.of(context);
                      events.add(snapshot.event.name);
                    } catch (error) {
                      errors.add(error);
                    }
                  },
                  child: const SizedBox(),
                ),
              ),
          ]),
        );
    await tester.pumpWidget(build(shown: true));

    await tester.pumpWidget(build(shown: false));

    expect(queue.items().map((item) => '${item.data}:${item.status.name}'),
        ['above:canceled', 'before:canceled']);
    expect(events, isEmpty);
    expect(errors, isEmpty);
  });

  testWidgets(
      'lets the listener show a SnackBar for updates sent while widgets are '
      'disposed', (tester) async {
    final id = queue.add('a');
    Widget build({required bool tile}) => MaterialApp(
          home: Scaffold(
            body: QueueItListener<String>(
              queue: queue,
              listener: (context, snapshot) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${snapshot.eventItem?.status.name}')));
              },
              // The tile cancels its download when it goes.
              child: tile
                  ? _Lifecycle(onDispose: () => queue.cancelById(id))
                  : const SizedBox(),
            ),
          ),
        );
    await tester.pumpWidget(build(tile: true));

    await tester.pumpWidget(build(tile: false));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('canceled'), findsOneWidget);
  });

  testWidgets('is not called on a page that cancels its work as it is popped',
      (tester) async {
    final id = queue.add('a');
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('home')),
    ));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (context) => _Lifecycle(
        onDeactivate: () => queue.cancelById(id),
        child: Scaffold(
          body: QueueItListener<String>(
            queue: queue,
            listener: (context, snapshot) {
              events.add(snapshot.event.name);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('canceled')));
            },
            child: const SizedBox(),
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();

    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(queue.items().single.status, QueueItemStatus.canceled);
    expect(events, isEmpty);
  });

  testWidgets(
      'hears the updates sent as widgets moving with it are deactivated, '
      'after the frame', (tester) async {
    final id = queue.add('a');
    final key = GlobalKey();
    Widget build({required bool moved}) {
      final panel = _Lifecycle(
        key: key,
        onDeactivate: () => queue.cancelById(id),
        child: QueueItListener<String>(
          queue: queue,
          listener: (context, snapshot) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${snapshot.eventItem?.status.name}')));
          },
          child: const SizedBox(),
        ),
      );
      return MaterialApp(
        home: Scaffold(
          body: moved
              ? Center(child: panel)
              : Padding(padding: EdgeInsets.zero, child: panel),
        ),
      );
    }

    await tester.pumpWidget(build(moved: false));
    await tester.pumpWidget(build(moved: true));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('canceled'), findsOneWidget);
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

  testWidgets('reports a listener that throws, and carries on', (tester) async {
    await tester.pumpWidget(QueueItListener<String>(
      queue: queue,
      listener: (context, snapshot) {
        events.add('${snapshot.eventItem?.data}');
        if (snapshot.eventItem?.data == 'throws') {
          throw StateError('listener failed');
        }
      },
      child: const SizedBox(),
    ));

    queue.add('throws');
    expect(tester.takeException(), isStateError);
    queue.add('next');
    expect(events, ['throws', 'next']);
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

  testWidgets('carries on when FlutterError.onError throws', (tester) async {
    Widget listener(String name) => QueueItListener<String>(
          queue: queue,
          listener: (context, snapshot) {
            final data = snapshot.eventItem?.data;
            events.add('$name:$data');
            if (data == 'throws') throw StateError('listener failed');
          },
          child: const SizedBox(),
        );
    final onError = FlutterError.onError;
    FlutterError.onError = (details) => throw details.exception;
    final zoneErrors = <Object>[];
    try {
      await runZonedGuarded(() async {
        await tester
            .pumpWidget(Column(children: [listener('a'), listener('b')]));

        /// Sent while Flutter builds, so held back until after the frame
        await tester.pumpWidget(Column(children: [
          listener('a'),
          listener('b'),
          _Lifecycle(
              onInit: () => queue
                ..add('throws')
                ..add('next')),
        ]));

        /// Sent right away
        queue.add('throws');
      }, (error, stack) => zoneErrors.add(error));
    } finally {
      FlutterError.onError = onError;
    }

    queue.add('after');
    expect(events, [
      'a:throws',
      'a:next',
      'b:throws',
      'b:next',
      'a:throws',
      'b:throws',
      'a:after',
      'b:after',
    ]);
    expect(zoneErrors, hasLength(4));
  });

  testWidgets("drops the old queue's events when moved and given a new queue",
      (tester) async {
    final other = QueueIt<String>(itemHandler: (item) {});
    addTearDown(other.dispose);
    final key = GlobalKey();
    Widget child(QueueIt<String> listened) => QueueItListener<String>(
          key: key,
          queue: listened,
          listener: (context, snapshot) =>
              events.add('${identical(listened, queue) ? 'queue' : 'other'}:'
                  '${snapshot.eventItem?.data}'),
          child: const SizedBox(),
        );
    await tester.pumpWidget(Column(children: [
      Padding(padding: EdgeInsets.zero, child: child(queue)),
    ]));

    await tester.pumpWidget(Column(children: [
      _Lifecycle(onInit: () => queue.add('during')),
      Center(child: child(other)),
      _Lifecycle(onInit: () => other.add('new')),
    ]));
    queue.add('ignored');

    expect(events, ['other:new']);
  });

  testWidgets(
      "drops the old queue's updates sent while building the frame it's "
      'given a new queue in', (tester) async {
    final other = QueueIt<String>(itemHandler: (item) {});
    addTearDown(other.dispose);
    // The key keeps the same listener when it's built after another widget.
    Widget child(QueueIt<String> listened) => QueueItListener<String>(
          key: const ValueKey('listener'),
          queue: listened,
          listener: (context, snapshot) =>
              events.add('${identical(listened, queue) ? 'queue' : 'other'}:'
                  '${snapshot.eventItem?.data}'),
          child: const SizedBox(),
        );
    await tester.pumpWidget(Column(children: [child(queue)]));
    queue.add('before');

    await tester.pumpWidget(Column(children: [
      child(other),
      _Lifecycle(onInit: () => other.add('during')),
    ]));
    other.add('after');

    expect(events, ['queue:before', 'other:during', 'other:after']);

    await tester.pumpWidget(Column(children: [
      _Lifecycle(key: const ValueKey('first'), onInit: () => other.add('old')),
      child(queue),
    ]));
    queue.add('new');

    expect(
        events, ['queue:before', 'other:during', 'other:after', 'queue:new']);
  });

  testWidgets(
      'gives the events sent as moved widgets come back to its new '
      'listener', (tester) async {
    final key = GlobalKey();
    Widget build({required bool moved}) {
      final child = QueueItListener<String>(
        key: key,
        queue: queue,
        listener: (context, snapshot) =>
            events.add('${moved ? 'new' : 'old'}:${snapshot.eventItem?.data}'),
        // Changes the queue when it's back in the tree after the move.
        child: _Lifecycle(onActivate: () => queue.add('activate')),
      );
      return Column(children: [
        moved
            ? Center(child: child)
            : Padding(padding: EdgeInsets.zero, child: child),
      ]);
    }

    await tester.pumpWidget(build(moved: false));
    await tester.pumpWidget(build(moved: true));

    expect(events, ['new:activate']);
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
  const _Lifecycle({
    super.key,
    this.onInit,
    this.onActivate,
    this.onDeactivate,
    this.onDispose,
    this.child = const SizedBox(),
  });

  final VoidCallback? onInit;
  final VoidCallback? onActivate;
  final VoidCallback? onDeactivate;
  final VoidCallback? onDispose;
  final Widget child;

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
  void activate() {
    super.activate();
    widget.onActivate?.call();
  }

  @override
  void deactivate() {
    widget.onDeactivate?.call();
    super.deactivate();
  }

  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
