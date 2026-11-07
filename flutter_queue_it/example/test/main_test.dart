import 'dart:convert';

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
  final _attempts = <String, int>{};

  /// The photos that finished uploading.
  final uploaded = <String>[];

  Stream<double> upload(Photo photo) async* {
    final attempt = _attempts.update(
      photo.name,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    for (var step = 1; step <= 10; step++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (step == 5 &&
          (failing.contains(photo.name) ||
              (attempt == 1 && flaky.contains(photo.name)))) {
        throw const UploadException('Connection lost');
      }
      yield step / 10;
    }
    uploaded.add(photo.name);
  }
}

Future<void> _pumpPage(WidgetTester tester, _Server server) async {
  await tester.pumpWidget(
    MaterialApp(
      home: example.UploadsPage(
        pickPhotos: _Gallery().pick,
        upload: server.upload,
      ),
    ),
  );
}

Future<void> _addPhotos(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add photos'));
  // Picking the photos takes a microtask, adding them a frame.
  await tester.pump();
  await tester.pump();
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

final _uploading = RegExp(r'^(Retry \d · )?\d+\.\d of 2\.0 MB$');

bool _isActive(String status) =>
    status.startsWith('Waiting') ||
    status.startsWith('Upload failed') ||
    _uploading.hasMatch(status);

/// Pumps 50 ms frames for [duration], so that animations run as they would on
/// a device.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 50);
  for (var time = Duration.zero; time < duration; time += frame) {
    await tester.pump(frame);
  }
}

/// Taps the button with [tooltip] in the photo at [index]. While the button
/// changes, the new one is the last.
Future<void> _tapIn(WidgetTester tester, int index, String tooltip) =>
    tester.tap(
      find
          .descendant(
            of: find.byType(ListTile).at(index),
            matching: find.byTooltip(tooltip),
          )
          .last,
    );

/// Pumps until every photo has finished, checking the parallel limit along the
/// way. Returns every status seen.
Future<Set<String>> _pumpUntilDone(WidgetTester tester) async {
  final seen = <String>{};
  for (var i = 0; i < 300; i++) {
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
  testWidgets('starts with no uploads', (tester) async {
    example.main();
    await tester.pump();
    expect(find.text('No uploads yet'), findsOneWidget);
    expect(find.byTooltip('Pause uploads'), findsOneWidget);
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
      'Uploaded · 2.0 MB',
      'Uploaded · 2.0 MB',
      "Couldn't upload: Connection lost",
      ...List.filled(3, 'Uploaded · 2.0 MB'),
    ]);
    expect(server.uploaded, unorderedEquals(_names(tester)..removeAt(2)));
    expect(find.text('Some photos failed'), findsOneWidget);
    expect(find.text('5 of 6 uploaded · 1 failed'), findsOneWidget);

    // The SnackBar's Retry adds the photo again, and this time it works.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("photo_3.jpg couldn't be uploaded"), findsOneWidget);
    server.failing.clear();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(_names(tester).last, 'photo_3.jpg');
    await _pumpUntilDone(tester);
    expect(_statuses(tester), List.filled(6, 'Uploaded · 2.0 MB'));
    expect(find.text('Uploads finished'), findsOneWidget);
    expect(find.text('6 of 6 uploaded'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear finished'));
    await _pumpOut(tester);
    expect(find.text('No uploads yet'), findsOneWidget);
  });

  testWidgets('removes, cancels and retries photos', (tester) async {
    final server = _Server();
    await _pumpPage(tester, server);
    await _addPhotos(tester);

    // Swipe away a photo while it's being uploaded.
    expect(_statuses(tester)[1], matches(_uploading));
    await tester.drag(find.byType(Dismissible).at(1), const Offset(-800, 0));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(_names(tester), [
      for (final n in [1, 3, 4, 5, 6]) 'photo_$n.jpg',
    ]);

    // Cancel a waiting photo and one being uploaded.
    await _tapIn(tester, 4, 'Cancel');
    await _tapIn(tester, 0, 'Cancel');
    await _pumpFor(tester, const Duration(milliseconds: 400));
    for (final index in [0, 4]) {
      final tile = find.byType(ListTile).at(index);
      expect(_statuses(tester)[index], 'Canceled');
      expect(
        find.descendant(of: tile, matching: find.byTooltip('Cancel')),
        findsNothing,
      );
      expect(
        find.descendant(of: tile, matching: find.byTooltip('Retry')),
        findsOneWidget,
      );
    }

    // Retrying a photo adds it again, at the end of the list.
    await _tapIn(tester, 0, 'Retry');
    await tester.pump();
    expect(_names(tester), [
      for (final n in [3, 4, 5, 6, 1]) 'photo_$n.jpg',
    ]);

    await _pumpUntilDone(tester);
    expect(_statuses(tester), [
      ...List.filled(3, 'Uploaded · 2.0 MB'),
      'Canceled',
      'Uploaded · 2.0 MB',
    ]);
    // The removed photo and the canceled attempt didn't finish uploading.
    expect(server.uploaded, [
      for (final n in [3, 4, 5, 1]) 'photo_$n.jpg',
    ]);

    await tester.tap(find.byTooltip('Clear finished'));
    await _pumpOut(tester);
    expect(find.text('No uploads yet'), findsOneWidget);
  });

  testWidgets('pauses and resumes', (tester) async {
    final server = _Server();
    await _pumpPage(tester, server);
    await _addPhotos(tester);

    // The photos being uploaded finish, and the others wait.
    await tester.tap(find.byTooltip('Pause uploads'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Paused'), findsOneWidget);
    expect(_statuses(tester), [
      ...List.filled(3, 'Uploaded · 2.0 MB'),
      ...List.filled(3, 'Waiting · 2.0 MB'),
    ]);

    await tester.tap(find.byTooltip('Resume uploads'));
    await _pumpUntilDone(tester);
    expect(_statuses(tester), List.filled(6, 'Uploaded · 2.0 MB'));
    expect(find.text('Uploads finished'), findsOneWidget);
    await _pumpOut(tester);
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
