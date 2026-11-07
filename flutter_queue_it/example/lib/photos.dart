import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A photo to upload. In a real app it would come from the user's gallery, for
/// example through the image_picker package.
class Photo {
  const Photo({required this.name, required this.size, required this.image});

  final String name;

  /// The size of the file, in bytes.
  final int size;

  final ImageProvider image;
}

/// Thrown when an upload fails.
class UploadException implements Exception {
  const UploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _random = math.Random();
var _picked = 0;

/// Stands in for a photo picker: returns six photos from Lorem Picsum.
Future<List<Photo>> pickSamplePhotos() async => [
  for (var i = 0; i < 6; i++) _samplePhoto(_picked++),
];

Photo _samplePhoto(int index) => Photo(
  name: 'IMG_${2041 + index}.jpg',
  size: 1500000 + _random.nextInt(3000000),
  image: NetworkImage('https://picsum.photos/seed/queue_it_$index/300'),
);

/// Pretends to upload [photo] at about 1.5 MB/s, so the example runs without a
/// server. Reports how much has been sent, from 0 to 1. About a third of the
/// attempts fail partway, to show off retries.
///
/// Swap in your own upload, for example with dio's `onSendProgress`.
Stream<double> fakeUpload(Photo photo) async* {
  final failAt = _random.nextDouble() < 0.3
      ? 0.2 + _random.nextDouble() * 0.6
      : null;
  final bytesPerTick = 75000 * (0.6 + _random.nextDouble() * 0.8);
  for (var sent = 0.0; sent < photo.size;) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    sent = math.min(sent + bytesPerTick, photo.size.toDouble());
    if (failAt != null && sent >= photo.size * failAt) {
      throw const UploadException('Connection lost');
    }
    yield sent / photo.size;
  }
}
