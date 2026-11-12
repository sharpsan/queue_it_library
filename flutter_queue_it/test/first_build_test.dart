import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_queue_it/flutter_queue_it.dart';
import 'package:flutter_test/flutter_test.dart';

/// A BuildOwner that never says it's building: in release mode
/// `debugBuilding` is always false.
class _ReleaseBuildOwner extends BuildOwner {
  _ReleaseBuildOwner() : super(focusManager: FocusManager());

  @override
  bool get debugBuilding => false;
}

/// A test binding that builds as a release app does.
class _ReleaseBinding extends AutomatedTestWidgetsFlutterBinding {
  final _releaseBuildOwner = _ReleaseBuildOwner();

  @override
  BuildOwner get buildOwner => _releaseBuildOwner;
}

/// Builds [child] in a tree of its own.
Element _attach(BuildOwner owner, Widget child) =>
    RenderObjectToWidgetAdapter<RenderBox>(
      container: RenderPositionedBox(),
      child: child,
    ).attachToRenderTree(owner);

/// Flutter builds an app's first widgets in runApp, outside a frame, and in
/// release mode nothing but the missing root element gives that build away.
/// A test body can't see it: flutter_test attaches widgets of its own before
/// each one. So setUpAll, which runs before anything is attached, builds the
/// widgets with the binding's BuildOwner, as runApp does. Keep these tests in
/// a file of their own.
void main() {
  final binding = _ReleaseBinding();
  final queue = QueueIt<String>(itemHandler: (item) {});
  final builds = <String?>[];
  final heard = <String>[];
  late final Element root;
  late final List<String> heardInFirstBuild;

  final offscreenQueue = QueueIt<String>(itemHandler: (item) {});
  final offscreenBuilds = <String?>[];
  final heardOffscreen = <String>[];
  late final List<String> heardOffscreenAtOnce;

  setUpAll(() {
    expect(binding.rootElement, isNull);
    root = _attach(
      binding.buildOwner,
      QueueItListener<String>(
        queue: queue,
        listener: (context, snapshot) => heard.add(snapshot.eventItem!.data),
        child: QueueItWidget<String>(
          queue: queue,
          builder: (context, snapshot) {
            builds.add(snapshot?.eventItem?.data);
            // Adds its work the first time it's built.
            if (queue.items().isEmpty) queue.add('from the first build');
            return const SizedBox();
          },
        ),
      ),
    );
    heardInFirstBuild = List.of(heard);

    // And a tree that isn't the app's, as offscreen rendering builds.
    final offscreenOwner = BuildOwner(focusManager: FocusManager());
    final offscreenRoot = _attach(
      offscreenOwner,
      QueueItListener<String>(
        queue: offscreenQueue,
        listener: (context, snapshot) =>
            heardOffscreen.add(snapshot.eventItem!.data),
        child: QueueItWidget<String>(
          queue: offscreenQueue,
          builder: (context, snapshot) {
            offscreenBuilds.add(snapshot?.eventItem?.data);
            return const SizedBox();
          },
        ),
      ),
    );
    offscreenQueue.add('before the app');
    heardOffscreenAtOnce = List.of(heardOffscreen);
    offscreenOwner.buildScope(offscreenRoot);
  });

  tearDownAll(() {
    queue.dispose();
    offscreenQueue.dispose();
  });

  testWidgets(
      "waits for the first frame with changes made in the app's first build",
      (tester) async {
    expect(heardInFirstBuild, isEmpty);

    // flutter_test has drawn a frame by now.
    expect(heard, ['from the first build']);
    binding.buildOwner.buildScope(root);
    expect(builds, [null, 'from the first build']);
  });

  testWidgets("doesn't wait for the app in a tree with its own BuildOwner",
      (tester) async {
    expect(heardOffscreenAtOnce, ['before the app']);
    expect(offscreenBuilds, [null, 'before the app']);
  });
}
