import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter_queue_it_example/main.dart' as example;
import 'package:flutter_queue_it_example/photos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// Hands out six 2 MB photos at a time: photo_1.jpg, photo_2.jpg and so on.
class _Gallery {
  var _count = 0;

  Future<List<Photo>> pick() async => [
    for (var i = 0; i < 6; i++)
      Photo(
        name: 'photo_${++_count}.jpg',
        size: 2000000,
        image: MemoryImage(_png),
      ),
  ];
}

/// Uploads each photo in ten steps of 100 ms. Every attempt at the photos in
/// [failing] fails halfway, and so does the first attempt at those in [flaky].
class _Server {
  _Server({Set<String>? failing, this.flaky = const {}})
    : failing = failing ?? {};

  final Set<String> failing;
  final Set<String> flaky;
  final attempts = <String, int>{};

  /// The photos that finished uploading.
  final uploaded = <String>[];

  /// The photos whose uploads were stopped partway.
  final stopped = <String>[];

  /// How many uploads are running, and the most there have been at once.
  var running = 0;
  var mostRunning = 0;

  Stream<double> upload(Photo photo) {
    final attempt = attempts.update(
      photo.name,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    final fails =
        failing.contains(photo.name) ||
        (attempt == 1 && flaky.contains(photo.name));
    late final StreamController<double> controller;
    Timer? timer;
    var step = 0;
    void finish() {
      timer!.cancel();
      running--;
    }

    controller = StreamController(
      onListen: () {
        running++;
        mostRunning = math.max(mostRunning, running);
        timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          step++;
          if (fails && step == 5) {
            finish();
            controller
              ..addError(const UploadException('Connection lost'))
              ..close();
          } else if (step == 10) {
            finish();
            uploaded.add(photo.name);
            controller
              ..add(1)
              ..close();
          } else {
            controller.add(step / 10);
          }
        });
      },
      onCancel: () {
        if (timer!.isActive) {
          finish();
          stopped.add(photo.name);
        }
      },
    );
    return controller.stream;
  }
}

/// Tests on a phone-sized screen, where the six photos added at a time fit
/// above the Add photos button.
void _usePhoneScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _page(_Server server) =>
    example.UploadsPage(pickPhotos: _Gallery().pick, upload: server.upload);

Future<void> _pumpPage(WidgetTester tester, _Server server) {
  _usePhoneScreen(tester);
  return tester.pumpWidget(MaterialApp(home: _page(server)));
}

Future<void> _addPhotos(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add photos'));
  // Picking the photos takes a microtask, adding them a frame.
  await tester.pump();
  await tester.pump();
}

/// Pumps 100 ms frames until [done], or fails after [limit].
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(seconds: 20),
}) async {
  for (var time = Duration.zero; !done(); time += _frame100) {
    if (time > limit) fail('Gave up waiting after $limit');
    await tester.pump(_frame100);
  }
}

const _frame100 = Duration(milliseconds: 100);

bool _showsSnackBar() => find.byType(SnackBar).evaluate().isNotEmpty;

/// Pumps 50 ms frames for [duration], so that animations run as they would on
/// a device.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 50);
  for (var time = Duration.zero; time < duration; time += frame) {
    await tester.pump(frame);
  }
}

/// The texts in each photo's tile: its name first, its status last.
List<List<String>> _tiles(WidgetTester tester) => [
  for (final tile in find.byType(ListTile).evaluate())
    [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byWidget(tile.widget),
          matching: find.byType(Text),
        ),
      ))
        text.data!,
    ],
];

List<String> _names(WidgetTester tester) => [
  for (final tile in _tiles(tester)) tile.first,
];

List<String> _statuses(WidgetTester tester) => [
  for (final tile in _tiles(tester)) tile.last,
];

Finder _buttonIn(int index, String tooltip) => find
    .descendant(
      of: find.byType(ListTile).at(index),
      matching: find.byTooltip(tooltip),
    )
    .last;

/// Taps the button with [tooltip] in the photo at [index].
Future<void> _tapIn(WidgetTester tester, int index, String tooltip) =>
    tester.tap(_buttonIn(index, tooltip));

final _uploading = RegExp(r'^(Retry \d · )?\d+\.\d of \d+\.\d MB$');
const _uploaded = 'Uploaded · 2.0 MB';
const _failed = "Couldn't upload: Connection lost";

bool _isActive(String status) =>
    status.startsWith('Waiting') ||
    status.startsWith('Upload failed') ||
    _uploading.hasMatch(status);

/// Pumps until every photo has finished, checking that no more than three
/// are uploading at a time. Returns every status seen.
Future<Set<String>> _pumpUntilDone(WidgetTester tester) async {
  final seen = <String>{};
  for (var i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    final statuses = _statuses(tester);
    seen.addAll(statuses);
    expect(statuses.where(_uploading.hasMatch).length, lessThanOrEqualTo(3));
    if (!statuses.any(_isActive)) return seen;
  }
  fail('The photos never finished: ${_statuses(tester)}');
}

/// Lets the SnackBars and animations finish.
Future<void> _pumpOut(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  // A tap that misses its button fails the test.
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('starts with no uploads', (tester) async {
    _usePhoneScreen(tester);
    example.main();
    await tester.pump();
    expect(find.text('No uploads yet'), findsOneWidget);
    expect(find.byTooltip('Pause uploads'), findsOneWidget);
    final clear = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.clear_all),
    );
    expect(clear.onPressed, isNull);
  });

  testWidgets('uploads the sample photos', (tester) async {
    _usePhoneScreen(tester);
    example.main();
    await tester.pump();
    await _addPhotos(tester);
    expect(_names(tester), everyElement(matches(r'^IMG_\d+\.jpg$')));

    // The uploads are random, so they can fail, but they all finish.
    await _pumpUntilDone(tester);
    expect(
      _statuses(tester),
      everyElement(anyOf(matches(r'^Uploaded · \d\.\d MB$'), _failed)),
    );
    await _pumpOut(tester);
  });

  testWidgets('uploads three at a time and retries the failures', (
    tester,
  ) async {
    final server = _Server(failing: {'photo_3.jpg'}, flaky: {'photo_2.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    expect(_statuses(tester), [
      ...List.filled(3, '0.0 of 2.0 MB'),
      ...List.filled(3, 'Waiting · 2.0 MB'),
    ]);
    expect(find.text('Uploading photos'), findsOneWidget);
    expect(find.text('0 of 6 uploaded'), findsOneWidget);

    final seen = await _pumpUntilDone(tester);
    expect(seen, contains('Upload failed, retrying'));
    expect(seen, contains(startsWith('Retry 1 · ')));
    expect(seen, contains(startsWith('Retry 2 · ')));
    expect(_statuses(tester), [
      _uploaded,
      _uploaded,
      _failed,
      ...List.filled(3, _uploaded),
    ]);
    expect(server.attempts['photo_3.jpg'], 3);
    expect(server.uploaded, unorderedEquals(_names(tester)..removeAt(2)));
    expect(server.mostRunning, 3);
    expect(find.text('Some photos failed'), findsOneWidget);
    expect(find.text('5 of 6 uploaded · 1 failed'), findsOneWidget);

    // The SnackBar's Retry tries the photo again, in its row.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("photo_3.jpg couldn't be uploaded"), findsOneWidget);
    server.failing.clear();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(_statuses(tester)[2], matches(_uploading));
    await _pumpUntilDone(tester);
    expect(_statuses(tester), List.filled(6, _uploaded));
    expect(find.text('All photos uploaded'), findsOneWidget);
    expect(find.text('6 of 6 uploaded'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear finished'));
    await _pumpOut(tester);
    expect(find.text('No uploads yet'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('shows the latest failure, and retries from the row', (
    tester,
  ) async {
    final server = _Server(failing: {'photo_1.jpg', 'photo_2.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntil(tester, _showsSnackBar);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(_statuses(tester).take(2), [_failed, _failed]);
    // Both photos failed at once, and only the second one's SnackBar shows.
    expect(find.text("photo_2.jpg couldn't be uploaded"), findsOneWidget);
    expect(find.text("photo_1.jpg couldn't be uploaded"), findsNothing);

    // Retrying photo 2 from its row hides its SnackBar.
    server.failing.clear();
    await _tapIn(tester, 1, 'Retry');
    await _pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsNothing);
    await _tapIn(tester, 0, 'Retry');
    await tester.pump();
    expect(_names(tester), [for (var n = 1; n <= 6; n++) 'photo_$n.jpg']);
    await _pumpUntilDone(tester);
    expect(_statuses(tester), List.filled(6, _uploaded));
    await _pumpOut(tester);
  });

  testWidgets('stops the uploads it cancels or removes', (tester) async {
    final server = _Server(flaky: {'photo_4.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);

    // Canceling stops the upload, and the next photo starts right away.
    await _tapIn(tester, 0, 'Cancel');
    expect(server.stopped, ['photo_1.jpg']);
    await tester.pump();
    expect(_statuses(tester)[0], 'Canceled');
    expect(_statuses(tester)[3], matches(_uploading));
    expect(server.running, 3);
    await _pumpFor(tester, const Duration(milliseconds: 400));

    // Swiping a photo away stops its upload too.
    await tester.drag(find.byType(Dismissible).at(1), const Offset(-800, 0));
    await _pumpFor(tester, const Duration(milliseconds: 700));
    expect(server.stopped, ['photo_1.jpg', 'photo_2.jpg']);
    expect(_names(tester), [
      for (final n in [1, 3, 4, 5, 6]) 'photo_$n.jpg',
    ]);

    // Cancel photo 4 while it waits to be retried.
    await _pumpUntil(
      tester,
      () => _statuses(tester)[2] == 'Upload failed, retrying',
    );
    await _tapIn(tester, 2, 'Cancel');
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(_statuses(tester)[2], 'Canceled');
    expect(server.attempts['photo_4.jpg'], 1);

    // Swipe away a photo that has finished uploading.
    expect(_statuses(tester)[1], _uploaded);
    await tester.drag(find.byType(Dismissible).at(1), const Offset(-800, 0));
    await _pumpFor(tester, const Duration(milliseconds: 700));
    expect(find.text('photo_3.jpg'), findsNothing);

    // Retry the photo canceled first, in its row.
    await _tapIn(tester, 0, 'Retry');
    await _pumpUntilDone(tester);
    expect(_names(tester), [
      for (final n in [1, 4, 5, 6]) 'photo_$n.jpg',
    ]);
    expect(_statuses(tester), [_uploaded, 'Canceled', _uploaded, _uploaded]);
    expect(
      server.uploaded,
      unorderedEquals([
        for (final n in [3, 5, 6, 1]) 'photo_$n.jpg',
      ]),
    );
    expect(server.mostRunning, 3);
  });

  testWidgets('pauses and resumes', (tester) async {
    final server = _Server();
    await _pumpPage(tester, server);
    await _addPhotos(tester);

    // The photos being uploaded finish, and the others wait.
    await tester.tap(find.byTooltip('Pause uploads'));
    await tester.pump();
    expect(find.text('Pausing…'), findsOneWidget);
    await _pumpFor(tester, const Duration(milliseconds: 1500));
    expect(find.text('Paused'), findsOneWidget);
    expect(_statuses(tester), [
      ...List.filled(3, _uploaded),
      ...List.filled(3, 'Waiting · 2.0 MB'),
    ]);

    await tester.tap(find.byTooltip('Resume uploads'));
    await _pumpUntilDone(tester);
    expect(_statuses(tester), List.filled(6, _uploaded));
    expect(find.text('All photos uploaded'), findsOneWidget);
    await _pumpOut(tester);
  });

  testWidgets('cancels every photo', (tester) async {
    final server = _Server();
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    for (var i = 0; i < 6; i++) {
      await _tapIn(tester, i, 'Cancel');
      await _pumpFor(tester, const Duration(milliseconds: 300));
    }
    expect(_statuses(tester), List.filled(6, 'Canceled'));
    expect(server.running, 0);
    expect(server.uploaded, isEmpty);
    expect(find.text('Uploads finished'), findsOneWidget);
    expect(find.text('0 of 6 uploaded · 6 canceled'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear finished'));
    await _pumpOut(tester);
    expect(find.text('No uploads yet'), findsOneWidget);
  });

  testWidgets('stops its uploads and SnackBars when it goes', (tester) async {
    final server = _Server(failing: {'photo_1.jpg'});
    final page = _page(server);
    final navigator = GlobalKey<NavigatorState>();
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Scaffold()),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (context) => page),
      ),
    );
    await tester.pumpAndSettle();
    await _addPhotos(tester);
    await _pumpUntil(tester, _showsSnackBar);
    // Add more, so some are uploading when the page goes.
    await _addPhotos(tester);
    expect(server.running, 3);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(server.running, 0);
    final uploaded = server.uploaded.length;
    await tester.pump(const Duration(seconds: 5));
    expect(server.uploaded, hasLength(uploaded));
  });

  testWidgets('ignores a quick second tap on a changing button', (
    tester,
  ) async {
    await _pumpPage(tester, _Server());
    await _addPhotos(tester);
    // Let the rows slide into place.
    await _pumpFor(tester, const Duration(milliseconds: 400));
    final button = tester.getCenter(_buttonIn(0, 'Cancel'));

    // The second tap lands where Retry is appearing, most of the way through
    // its 250 ms change.
    await tester.tapAt(button);
    await _pumpFor(tester, const Duration(milliseconds: 250));
    await tester.tapAt(button);
    await _pumpFor(tester, const Duration(milliseconds: 400));
    expect(_statuses(tester)[0], 'Canceled');

    // And here, where Cancel is appearing.
    await tester.tapAt(button);
    await _pumpFor(tester, const Duration(milliseconds: 250));
    await tester.tapAt(button);
    await _pumpFor(tester, const Duration(milliseconds: 400));
    expect(_statuses(tester)[0], isNot('Canceled'));
    expect(_names(tester).first, 'photo_1.jpg');
    await _pumpUntilDone(tester);
  });

  testWidgets('slides new photos in, even as the queue changes', (
    tester,
  ) async {
    await _pumpPage(tester, _Server());
    await tester.tap(find.byTooltip('Pause uploads'));
    await _addPhotos(tester);
    SlideTransition slide() => tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byType(ListTile).first,
            matching: find.byType(SlideTransition),
          )
          .first,
    );

    await tester.pump(const Duration(milliseconds: 50));
    final sliding = slide().position;
    expect(sliding.value.dy, greaterThan(0));

    // An update from the queue rebuilds the rows, and they keep sliding.
    await tester.tap(find.byTooltip('Resume uploads'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(slide().position, same(sliding));
    expect(sliding.value.dy, greaterThan(0));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    expect(sliding.value, Offset.zero);
    await _pumpUntilDone(tester);
  });

  testWidgets('lets screen readers remove a photo', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final server = _Server();
      await _pumpPage(tester, server);
      await _addPhotos(tester);
      // Screen readers skip the rows until they've faded in.
      await _pumpFor(tester, const Duration(milliseconds: 450));

      const remove = CustomSemanticsAction(label: 'Remove');
      final removeId = CustomSemanticsAction.getIdentifier(remove);
      final photos = find.semantics.byPredicate(
        (node) =>
            node.getSemanticsData().customSemanticsActionIds?.contains(
              removeId,
            ) ??
            false,
      );
      expect(photos, findsExactly(6));
      tester.semantics.customAction(photos.at(1), remove);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(_names(tester), [
        for (final n in [1, 3, 4, 5, 6]) 'photo_$n.jpg',
      ]);
      expect(server.stopped, ['photo_2.jpg']);
      await _pumpUntilDone(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('keeps Cancel working as a photo starts uploading', (
    tester,
  ) async {
    await _pumpPage(tester, _Server());
    await _addPhotos(tester);
    await _pumpFor(tester, const Duration(milliseconds: 400));
    expect(_statuses(tester)[3], 'Waiting · 2.0 MB');

    // Photo 4 starts when photo 1 is canceled, and its Cancel still works.
    await _tapIn(tester, 0, 'Cancel');
    await _pumpFor(tester, const Duration(milliseconds: 50));
    expect(_statuses(tester)[3], matches(_uploading));
    await _tapIn(tester, 3, 'Cancel');
    await _pumpFor(tester, const Duration(milliseconds: 400));
    expect(_statuses(tester)[3], 'Canceled');
    await _pumpUntilDone(tester);
  });

  testWidgets('removes a photo retried from its SnackBar as it goes', (
    tester,
  ) async {
    final server = _Server(failing: {'photo_1.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntil(tester, _showsSnackBar);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    server.failing.clear();

    // Retry the photo while its row is closing up.
    await tester.drag(find.byType(Dismissible).at(0), const Offset(-800, 0));
    for (var i = 0; find.byType(SizeTransition).evaluate().isEmpty; i++) {
      if (i == 30) fail("The row didn't close up");
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The row finishes closing up in the same frame, before it rebuilds.
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpFor(tester, const Duration(milliseconds: 200));
    expect(find.text('photo_1.jpg'), findsNothing);
    await _pumpUntilDone(tester);
    expect(server.uploaded, isNot(contains('photo_1.jpg')));
    expect(server.running, 0);
  });

  testWidgets('stops the sample uploads when the page goes', (tester) async {
    _usePhoneScreen(tester);
    example.main();
    await tester.pump();
    await _addPhotos(tester);
    await _pumpFor(tester, const Duration(milliseconds: 700));
    await _tapIn(tester, 0, 'Cancel');
    await tester.pump();
    // No upload timers are left once the page has gone.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removes two photos swiped one after the other', (tester) async {
    await _pumpPage(tester, _Server());
    await tester.tap(find.byTooltip('Pause uploads'));
    await _addPhotos(tester);
    final names = _names(tester);

    // The second swipe starts while the first photo is still going away.
    await tester.drag(find.byType(Dismissible).at(0), const Offset(-800, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(Dismissible).at(1), const Offset(-800, 0));
    await tester.pumpAndSettle();

    expect(find.text(names[0]), findsNothing);
    expect(find.text(names[1]), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(4));
  });
}
