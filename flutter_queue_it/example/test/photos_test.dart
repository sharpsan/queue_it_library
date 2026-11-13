import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_queue_it_example/photos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the sample photos are bundled with the example', (tester) async {
    // Two picks: the second one starts over with the same six photos.
    final photos = [...await pickSamplePhotos(), ...await pickSamplePhotos()];
    expect(photos, hasLength(12));
    expect({for (final photo in photos) photo.name}, hasLength(12));
    final keys = <String>{};
    for (final photo in photos) {
      final image = photo.image;
      expect(image, isA<AssetImage>());
      final key = (image as AssetImage).keyName;
      keys.add(key);
      // Fails if the file isn't listed under `assets` in the pubspec.
      final bytes = await tester.runAsync(() => rootBundle.load(key));
      expect(bytes!.lengthInBytes, greaterThan(1000), reason: key);
    }
    expect(keys, hasLength(6));
  });
}
