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

/// Hands out 2 MB photos, six at a time unless [perPick] says otherwise:
/// photo_1.jpg, photo_2.jpg and so on.
class _Gallery {
  _Gallery({this.perPick = 6});

  /// How many photos each pick returns.
  final int perPick;
  var _count = 0;

  Future<List<Photo>> pick() async => [
    for (var i = 0; i < perPick; i++)
      Photo(
        name: 'photo_${++_count}.jpg',
        size: 2000000,
        image: MemoryImage(_png),
      ),
  ];
}

/// Uploads each photo in ten steps of 100 ms. Every attempt at the photos in
/// [failing] fails halfway, and so does the first attempt at those in [flaky],
/// and any attempt [failWhen] picks.
class _Server {
  _Server({Set<String>? failing, this.flaky = const {}, this.failWhen})
    : failing = failing ?? {};

  final Set<String> failing;
  final Set<String> flaky;

  /// Whether an attempt at a photo fails, on top of [failing] and [flaky].
  final bool Function(String name, int attempt)? failWhen;
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
        (attempt == 1 && flaky.contains(photo.name)) ||
        (failWhen?.call(photo.name, attempt) ?? false);
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
void _usePhoneScreen(WidgetTester tester) =>
    _useScreen(tester, const Size(360, 780));

/// Tests on a screen of [size] logical pixels.
void _useScreen(WidgetTester tester, Size size, {double pixelRatio = 3}) {
  tester.view
    ..physicalSize = size * pixelRatio
    ..devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
}

Widget _page(_Server server, {_Gallery? gallery}) => example.UploadsPage(
  pickPhotos: (gallery ?? _Gallery()).pick,
  upload: server.upload,
);

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

/// Pumps frames of [step] until [done], or fails after [limit].
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(seconds: 20),
  Duration step = _frame100,
}) async {
  for (var time = Duration.zero; !done(); time += step) {
    if (time > limit) fail('Gave up waiting after $limit');
    await tester.pump(step);
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

const _frame50 = Duration(milliseconds: 50);

/// The Clear finished button.
IconButton _clearButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.clear_all));

/// Pumps the page in a left-to-right or right-to-left app.
Future<void> _pumpPageIn(
  WidgetTester tester,
  _Server server,
  TextDirection direction,
) {
  _usePhoneScreen(tester);
  return tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          Directionality(textDirection: direction, child: child!),
      home: _page(server),
    ),
  );
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

  testWidgets('waits a second longer before each retry', (tester) async {
    final server = _Server(failing: {'photo_1.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);

    // The first attempt fails after 0.5 s, and the first retry starts a second
    // later.
    await _pumpFor(tester, const Duration(milliseconds: 1300));
    expect(server.attempts['photo_1.jpg'], 1);
    await _pumpFor(tester, const Duration(milliseconds: 400));
    expect(server.attempts['photo_1.jpg'], 2);
    // That one fails at 2 s, and the second retry starts two seconds later.
    await _pumpFor(tester, const Duration(milliseconds: 1800));
    expect(server.attempts['photo_1.jpg'], 2);
    await _pumpFor(tester, const Duration(milliseconds: 800));
    expect(server.attempts['photo_1.jpg'], 3);
    await _pumpUntilDone(tester);
    await _pumpOut(tester);
  });

  testWidgets('starts each attempt from nothing sent', (tester) async {
    await _pumpPage(tester, _Server(flaky: {'photo_1.jpg'}));
    await _addPhotos(tester);
    final seen = <String>[];
    for (var i = 0; i < 60 && !seen.any((s) => s.startsWith('Retry 1')); i++) {
      await tester.pump(const Duration(milliseconds: 50));
      seen.add(_statuses(tester)[0]);
    }

    // It had sent 0.8 MB when the first attempt failed.
    expect(
      seen,
      containsAllInOrder(['0.8 of 2.0 MB', 'Upload failed, retrying']),
    );
    expect(seen.last, 'Retry 1 · 0.0 of 2.0 MB');
    await _pumpUntilDone(tester);
  });

  testWidgets('stops an upload when it fails', (tester) async {
    var started = 0;
    var stopped = 0;
    Stream<double> upload(Photo photo) {
      // Fails without closing its stream.
      late final StreamController<double> controller;
      controller = StreamController(
        onListen: () {
          started++;
          controller.addError(const UploadException('Connection lost'));
        },
        onCancel: () => stopped++,
      );
      return controller.stream;
    }

    _usePhoneScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: example.UploadsPage(pickPhotos: _Gallery().pick, upload: upload),
      ),
    );
    await _addPhotos(tester);
    await tester.pump();
    expect(started, greaterThan(0));
    expect(stopped, started);

    await _pumpUntilDone(tester);
    expect(_statuses(tester), List.filled(6, _failed));
    expect(started, 18);
    expect(stopped, 18);
    await _pumpOut(tester);
  });

  testWidgets("hides a photo's SnackBar when the photo is removed", (
    tester,
  ) async {
    await _pumpPage(tester, _Server(failing: {'photo_1.jpg'}));
    await _addPhotos(tester);
    await _pumpUntil(tester, _showsSnackBar);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text("photo_1.jpg couldn't be uploaded"), findsOneWidget);

    await tester.drag(find.byType(Dismissible).at(0), const Offset(-800, 0));
    // Long before the SnackBar would go by itself.
    await _pumpFor(tester, const Duration(milliseconds: 1500));

    expect(find.text('photo_1.jpg'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await _pumpUntilDone(tester);
  });

  testWidgets("keeps a photo's SnackBar when another photo is removed", (
    tester,
  ) async {
    await _pumpPage(tester, _Server(failing: {'photo_1.jpg'}));
    await _addPhotos(tester);
    await _pumpUntil(tester, _showsSnackBar);
    await _pumpFor(tester, const Duration(milliseconds: 500));

    await tester.drag(find.byType(Dismissible).at(1), const Offset(-800, 0));
    await _pumpFor(tester, const Duration(milliseconds: 1500));

    expect(find.text('photo_2.jpg'), findsNothing);
    expect(find.text("photo_1.jpg couldn't be uploaded"), findsOneWidget);
    await _pumpOut(tester);
  });

  testWidgets('retries a photo once when Retry is tapped twice in a frame', (
    tester,
  ) async {
    final server = _Server(failing: {'photo_1.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntilDone(tester);
    await _pumpOut(tester);
    expect(server.attempts['photo_1.jpg'], 3);
    server.failing.clear();

    await _tapIn(tester, 0, 'Retry');
    await _tapIn(tester, 0, 'Retry');
    await _pumpUntilDone(tester);

    expect(_statuses(tester), List.filled(6, _uploaded));
    expect(server.attempts['photo_1.jpg'], 4);
    expect(
      server.uploaded.where((name) => name == 'photo_1.jpg'),
      hasLength(1),
    );
  });

  testWidgets('has nothing left to clear after a retried photo is cleared', (
    tester,
  ) async {
    final server = _Server(failing: {'photo_1.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntilDone(tester);
    await _pumpOut(tester);
    server.failing.clear();
    await _tapIn(tester, 0, 'Retry');
    await _pumpUntilDone(tester);
    expect(_statuses(tester), List.filled(6, _uploaded));

    await tester.tap(find.byTooltip('Clear finished'));
    await _pumpOut(tester);

    expect(find.text('No uploads yet'), findsOneWidget);
    expect(_clearButton(tester).onPressed, isNull);
  });

  testWidgets('Clear finished leaves the photos that are not finished', (
    tester,
  ) async {
    final server = _Server();
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await tester.tap(find.byTooltip('Pause uploads'));
    await _pumpFor(tester, const Duration(milliseconds: 1500));
    expect(_statuses(tester), [
      ...List.filled(3, _uploaded),
      ...List.filled(3, 'Waiting · 2.0 MB'),
    ]);

    await tester.tap(find.byTooltip('Clear finished'));
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(_names(tester), [for (var n = 4; n <= 6; n++) 'photo_$n.jpg']);
    expect(_statuses(tester), List.filled(3, 'Waiting · 2.0 MB'));
    expect(_clearButton(tester).onPressed, isNull);
    await tester.tap(find.byTooltip('Resume uploads'));
    await _pumpUntilDone(tester);
    expect(server.uploaded, hasLength(6));
  });

  testWidgets('Clear finished clears the photos that failed', (tester) async {
    await _pumpPage(tester, _Server(failing: {'photo_1.jpg', 'photo_2.jpg'}));
    await _addPhotos(tester);
    await _pumpUntilDone(tester);
    await _pumpOut(tester);
    expect(_statuses(tester).take(2), [_failed, _failed]);

    await tester.tap(find.byTooltip('Clear finished'));
    await _pumpOut(tester);

    expect(find.text('No uploads yet'), findsOneWidget);
    expect(_clearButton(tester).onPressed, isNull);
  });

  testWidgets('ignores photos picked after the page has gone', (tester) async {
    final picked = Completer<List<Photo>>();
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: example.UploadsPage(
          pickPhotos: () => picked.future,
          upload: _Server().upload,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpWidget(const SizedBox());

    picked.complete(await _Gallery().pick());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('uploads photos added after pausing and resuming', (
    tester,
  ) async {
    final server = _Server();
    // Tall enough for twelve rows: rows off the screen aren't built.
    _useScreen(tester, const Size(360, 1400), pixelRatio: 1);
    await tester.pumpWidget(MaterialApp(home: _page(server)));
    await _addPhotos(tester);
    await tester.tap(find.byTooltip('Pause uploads'));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Resume uploads'));
    await _pumpUntilDone(tester);
    expect(server.uploaded, hasLength(6));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byTooltip('Pause uploads'), findsOneWidget);
    await _addPhotos(tester);
    await _pumpUntilDone(tester);
    expect(server.uploaded, hasLength(12));
    await _pumpOut(tester);
  });

  testWidgets('only a swipe towards the start removes a photo', (tester) async {
    final server = _Server();
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntilDone(tester);
    await tester.fling(find.byType(ListTile).first, const Offset(300, 0), 1000);
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(_names(tester), hasLength(6));
    await tester.fling(
      find.byType(ListTile).first,
      const Offset(-300, 0),
      1000,
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(_names(tester), hasLength(5));
    await _pumpOut(tester);
  });

  testWidgets('stops a swiped photo before its row has gone', (tester) async {
    final server = _Server();
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.fling(
      find.byType(ListTile).first,
      const Offset(-300, 0),
      1000,
    );
    await _pumpUntil(tester, () => server.stopped.isNotEmpty, step: _frame50);
    expect(server.stopped, ['photo_1.jpg']);
    // Its row is still closing.
    expect(find.byType(Dismissible), findsNWidgets(6));
    await _pumpUntilDone(tester);
    expect(_names(tester), isNot(contains('photo_1.jpg')));
    await _pumpOut(tester);
  });

  testWidgets("doesn't slide in the rows scrolled to later", (tester) async {
    final server = _Server();
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      MaterialApp(home: _page(server, gallery: _Gallery(perPick: 30))),
    );
    await tester.tap(find.byTooltip('Pause uploads'));
    await _addPhotos(tester);
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('photo_25.jpg'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pump(_frame50);
    expect(find.text('photo_25.jpg'), findsOneWidget);
    final slide = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.text('photo_25.jpg'),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    expect(slide.position.value, Offset.zero);
    await _pumpOut(tester);
  });

  testWidgets('the failure SnackBar goes after a few seconds', (tester) async {
    final server = _Server(failing: {'photo_1.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntil(tester, _showsSnackBar, step: _frame50);
    await _pumpFor(tester, const Duration(seconds: 6));
    expect(find.byType(SnackBar), findsNothing);
    await _pumpOut(tester);
  });

  testWidgets("a SnackBar's Retry does nothing once the row has retried", (
    tester,
  ) async {
    final server = _Server(
      failWhen: (name, attempt) => name == 'photo_1.jpg' && attempt <= 3,
    );
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntil(tester, _showsSnackBar, step: _frame50);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(server.attempts['photo_1.jpg'], 3);
    await _tapIn(tester, 0, 'Retry');
    await tester.pump(_frame50);
    // The SnackBar is on its way out and still takes taps.
    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    expect(server.attempts['photo_1.jpg'], 4);
    expect(server.running, 1);
    await _pumpUntilDone(tester);
    expect(server.uploaded, hasLength(6));
    expect(server.stopped, isEmpty);
    await _pumpOut(tester);
  });

  // photo_1 runs out of retries at 4.5 s and photo_4 at 5.0 s, while photo_1's
  // SnackBar is showing.
  testWidgets('no SnackBar for a photo cleared while the previous SnackBar '
      'is hiding', (tester) async {
    final server = _Server(failing: {'photo_1.jpg', 'photo_4.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntil(
      tester,
      () => find.text("photo_1.jpg couldn't be uploaded").evaluate().isNotEmpty,
      step: const Duration(milliseconds: 50),
    );
    // Wait for photo_4 to fail for good.
    await _pumpUntil(
      tester,
      () => _statuses(tester)[3] == _failed,
      step: const Duration(milliseconds: 50),
    );
    expect(_statuses(tester)[0], _failed);
    // photo_1's SnackBar is on its way out; photo_4's is waiting behind it.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Clear finished'));
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('No uploads yet'), findsOneWidget);
    // A SnackBar about a photo that's no longer there, with a Retry that does
    // nothing:
    expect(find.byType(SnackBar), findsNothing);
    await _pumpOut(tester);
  });

  testWidgets('no SnackBar for a photo retried from its row while the '
      'previous SnackBar is hiding', (tester) async {
    final server = _Server(failing: {'photo_1.jpg', 'photo_4.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntil(
      tester,
      () => _statuses(tester)[3] == _failed,
      step: const Duration(milliseconds: 50),
    );
    server.failing.clear();
    // Tap photo_4's Retry as soon as it takes taps.
    var tapped = false;
    for (var i = 0; i < 40 && !tapped; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final retry = _buttonIn(3, 'Retry');
      if (retry.evaluate().isEmpty) continue;
      if (retry.hitTestable().evaluate().isEmpty) continue;
      await tester.tap(retry);
      tapped = true;
      // ignore: avoid_print
      print('tapped Retry ${(i + 1) * 16} ms after the failure showed');
    }
    expect(tapped, isTrue);
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(_statuses(tester)[3], isNot(_failed));
    expect(find.text("photo_4.jpg couldn't be uploaded"), findsNothing);
    await _pumpUntilDone(tester);
    await _pumpOut(tester);
  });

  testWidgets('retrying from a SnackBar on its way out keeps the next '
      'SnackBar tied to its photo', (tester) async {
    final server = _Server(failing: {'photo_1.jpg', 'photo_4.jpg'});
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpUntil(
      tester,
      () => _statuses(tester)[3] == _failed,
      step: const Duration(milliseconds: 50),
    );
    server.failing.clear();
    // photo_1's SnackBar is hiding. Tap its Retry.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text("photo_1.jpg couldn't be uploaded"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    // photo_4's SnackBar is showing now. Retry photo_4 from its row.
    expect(find.text("photo_4.jpg couldn't be uploaded"), findsOneWidget);
    await _tapIn(tester, 3, 'Retry');
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(_statuses(tester)[3], isNot(_failed));
    expect(find.text("photo_4.jpg couldn't be uploaded"), findsNothing);
    await _pumpUntilDone(tester);
    await _pumpOut(tester);
  });

  testWidgets('three quick taps on Pause', (tester) async {
    final server = _Server();
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    await _pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Uploading photos'), findsOneWidget);

    // Pause and Resume are the same spot. Taps at 0, 100 and 200 ms.
    final spot = tester.getCenter(find.byTooltip('Pause uploads'));
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Resume uploads'), findsOneWidget);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Pause uploads'), findsOneWidget);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Resume uploads'), findsOneWidget);
    await tester.tapAt(spot);
    await _pumpUntilDone(tester);
    await _pumpOut(tester);
  });

  testWidgets('shows only the latest SnackBar when photos run out of retries '
      'one after the other', (tester) async {
    final server = _Server(
      failing: {for (var n = 1; n <= 6; n++) 'photo_$n.jpg'},
    );
    await _pumpPage(tester, server);
    await _addPhotos(tester);
    // The first three run out together, and the other three half a second
    // later, while the first SnackBar is still up.
    await _pumpUntil(
      tester,
      () => _statuses(tester).every((status) => status == _failed),
      step: _frame50,
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text("photo_6.jpg couldn't be uploaded"), findsOneWidget);
    // And none of the earlier ones comes back after it.
    await _pumpFor(tester, const Duration(seconds: 5));
    expect(find.byType(SnackBar), findsNothing);
    await _pumpOut(tester);
  });

  for (final direction in TextDirection.values) {
    final rtl = direction == TextDirection.rtl;

    testWidgets('${direction.name}: swiping a photo uncovers the delete icon', (
      tester,
    ) async {
      final server = _Server();
      await _pumpPageIn(tester, server, direction);
      await _addPhotos(tester);
      await _pumpFor(tester, const Duration(milliseconds: 500));

      // Swipe from the end to the start: leftwards, or rightwards in RTL.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Dismissible).first),
      );
      await gesture.moveBy(Offset(rtl ? 30 : -30, 0));
      await gesture.moveBy(Offset(rtl ? 90 : -90, 0));
      await tester.pump();

      final tile = tester.getRect(find.byType(ListTile).first);
      final icon = tester.getRect(
        find.descendant(
          of: find.byType(Dismissible).first,
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      // The tile has moved; the icon is in the strip it uncovered.
      if (rtl) {
        expect(tile.left, greaterThan(80));
        expect(icon.right, lessThanOrEqualTo(tile.left));
      } else {
        expect(tile.right, lessThan(280));
        expect(icon.left, greaterThanOrEqualTo(tile.right));
      }
      await gesture.up();
      await _pumpUntilDone(tester);
      await _pumpOut(tester);
    });

    testWidgets('${direction.name}: a status that changes stays at the start '
        'of its line', (tester) async {
      final server = _Server();
      await _pumpPageIn(tester, server, direction);
      await _addPhotos(tester);
      // The fourth photo waits, then uploads: both lines are there while they
      // switch.
      Iterable<Element> lines() => find
          .descendant(
            of: find.byType(ListTile).at(3),
            matching: find.byType(Text),
          )
          .evaluate()
          .skip(1);
      for (var i = 0; i < 100 && lines().length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(lines(), hasLength(2));
      await tester.pump(const Duration(milliseconds: 32));
      final rects = [
        for (final line in lines()) tester.getRect(find.byWidget(line.widget)),
      ];
      expect(rects[0].width, isNot(rects[1].width));
      if (rtl) {
        expect(rects[0].right, rects[1].right);
      } else {
        expect(rects[0].left, rects[1].left);
      }
      await _pumpUntilDone(tester);
      await _pumpOut(tester);
    });
  }
}
