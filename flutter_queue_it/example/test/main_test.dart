import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_queue_it_example/main.dart' as example;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// Serves [_png] for every image but the first one requested, which always
/// fails, so the app has an image that runs out of retries.
class _Server {
  Uri? _failing;
  var downloads = 0;

  MockClient get client => MockClient((request) async {
        _failing ??= request.url;
        if (request.url == _failing) return http.Response('', 500);
        downloads++;
        return http.Response.bytes(_png, 200);
      });
}

/// The subtitle of each image in the list.
List<String> _subtitles(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        (tile.subtitle! as Text).data!,
    ];

bool _isFinished(String subtitle) =>
    subtitle.startsWith('Downloaded in') || subtitle.startsWith('Failed: ');

/// Pumps until every image has finished, checking the parallel limit along
/// the way. Returns every subtitle seen.
Future<Set<String>> _pumpUntilFinished(WidgetTester tester) async {
  final seen = <String>{};
  // Each attempt takes up to 2 s, and the retries wait 1 s and 2 s.
  for (var i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    final subtitles = _subtitles(tester);
    seen.addAll(subtitles);
    expect(
      subtitles.where((subtitle) => subtitle.startsWith('Downloading')).length,
      lessThanOrEqualTo(3),
    );
    if (subtitles
        .every((subtitle) => _isFinished(subtitle) || subtitle == 'Canceled')) {
      return seen;
    }
  }
  fail('The images never finished: ${_subtitles(tester)}');
}

/// Pumps until every SnackBar has been shown and hidden. Returns their texts.
Future<List<String>> _pumpSnackBars(WidgetTester tester) async {
  final texts = <String>[];
  for (var i = 0; i < 200; i++) {
    final shown = tester
        .widgetList<SnackBar>(find.byType(SnackBar))
        .map((snackBar) => (snackBar.content as Text).data!);
    if (shown.isEmpty) return texts;
    for (final text in shown) {
      if (!texts.contains(text)) texts.add(text);
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  fail('The SnackBars never went away');
}

void main() {
  testWidgets('downloads the images, retrying the failures', (tester) async {
    final server = _Server();
    await http.runWithClient(() async {
      example.main();
      await tester.pump();
      expect(find.text('Add images to download'), findsOneWidget);

      await tester.tap(find.byTooltip('Add five images'));
      await tester.pump();
      expect(_subtitles(tester), List.filled(5, 'Waiting'));

      await tester.tap(find.byTooltip('Start the queue'));
      await tester.pump();
      expect(find.byTooltip('Stop the queue'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      final seen = await _pumpUntilFinished(tester);
      expect(seen, contains(startsWith('Waiting for retry 1 of 2: ')));
      expect(seen, contains('Downloading, retry 2'));

      final subtitles = _subtitles(tester);
      final downloaded = subtitles.where((s) => s.startsWith('Downloaded in'));
      final failed = subtitles.where((s) => s.startsWith('Failed: '));
      expect(downloaded.length + failed.length, 5);
      expect(failed, isNotEmpty);
      expect(failed, everyElement(startsWith('Failed: Exception: ')));
      expect(find.byType(Image), findsNWidgets(downloaded.length));
      expect(server.downloads, downloaded.length);
      // The queue keeps running, but it has nothing left to process.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byTooltip('Stop the queue'), findsOneWidget);

      // A message for each image that ran out of retries.
      final titles = [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          (tile.title! as Text).data!,
      ];
      final failedIds = [
        for (var i = 0; i < 5; i++)
          if (subtitles[i].startsWith('Failed: ')) titles[i],
      ];
      final messages = await _pumpSnackBars(tester);
      expect(messages, hasLength(failedIds.length));
      for (final id in failedIds) {
        expect(messages, contains(startsWith('$id failed: Exception: ')));
      }

      await tester.tap(find.byTooltip('Remove finished images'));
      await tester.pump();
      expect(find.text('Add images to download'), findsOneWidget);

      await tester.tap(find.byTooltip('Stop the queue'));
      await tester.pump();
      expect(find.byTooltip('Start the queue'), findsOneWidget);
    }, () => server.client);
  });

  testWidgets('removes two images swiped one after the other', (tester) async {
    final server = _Server();
    await http.runWithClient(() async {
      example.main();
      await tester.pump();
      await tester.tap(find.byTooltip('Add five images'));
      await tester.pump();
      final titles = [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          (tile.title! as Text).data!,
      ];

      // The second swipe starts while the first image is still going away.
      await tester.drag(find.byType(Dismissible).at(0), const Offset(-800, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.drag(find.byType(Dismissible).at(1), const Offset(-800, 0));
      await tester.pumpAndSettle();

      expect(find.text(titles[0]), findsNothing);
      expect(find.text(titles[1]), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(3));
    }, () => server.client);
  });

  testWidgets('cancels and removes images', (tester) async {
    final server = _Server();
    await http.runWithClient(() async {
      example.main();
      await tester.pump();
      await tester.tap(find.byTooltip('Add five images'));
      await tester.tap(find.byTooltip('Start the queue'));
      await tester.pump();
      expect(_subtitles(tester), [
        ...List.filled(3, 'Downloading'),
        ...List.filled(2, 'Waiting'),
      ]);

      // Cancel a waiting image and a downloading one.
      await tester.tap(find.byTooltip('Cancel').at(4));
      await tester.tap(find.byTooltip('Cancel').at(0));
      await tester.pump();
      expect(_subtitles(tester)[0], 'Canceled');
      expect(_subtitles(tester)[4], 'Canceled');
      expect(find.byTooltip('Cancel'), findsNWidgets(3));

      // Swipe the second image away.
      final removed = (tester
              .widgetList<ListTile>(find.byType(ListTile))
              .elementAt(1)
              .title! as Text)
          .data!;
      await tester.drag(find.byType(Dismissible).at(1), const Offset(-800, 0));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(removed), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(4));

      await _pumpUntilFinished(tester);
      final subtitles = _subtitles(tester);
      expect(subtitles.first, 'Canceled');
      expect(subtitles.last, 'Canceled');
      expect(subtitles.where(_isFinished), hasLength(2));

      await _pumpSnackBars(tester);
      await tester.tap(find.byTooltip('Stop the queue'));
      await tester.pump();

      // The canceled and removed images' handlers wait out their delay, up
      // to 2 s, before they see they're done.
      await tester.pump(const Duration(seconds: 2));

      // Starting the queue again rebuilds the list. The canceled images
      // weren't downloaded after all.
      await tester.tap(find.byTooltip('Start the queue'));
      await tester.pump();
      for (final tile in [
        find.byType(ListTile).first,
        find.byType(ListTile).last,
      ]) {
        expect(find.descendant(of: tile, matching: find.byType(Image)),
            findsNothing);
      }
      await tester.tap(find.byTooltip('Stop the queue'));
      await tester.pump();
    }, () => server.client);
  });
}
