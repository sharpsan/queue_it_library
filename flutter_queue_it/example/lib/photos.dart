import 'dart:async';
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

/// Stands in for a photo picker: returns the six photos in `assets/photos/`.
Future<List<Photo>> pickSamplePhotos() async => [
  for (var i = 0; i < 6; i++) _samplePhoto(_picked++),
];

Photo _samplePhoto(int index) => Photo(
  name: 'IMG_${2041 + index}.jpg',
  size: 1500000 + _random.nextInt(3000000),
  image: AssetImage('assets/photos/${index % 6 + 1}.jpg'),
);

/// Pretends to upload [photo] at about 1.5 MB/s, so the example runs without a
/// server. Reports how much has been sent, from 0 to 1, and stops when its
/// subscription is canceled. About a third of the attempts fail partway, to
/// show off retries.
///
/// Swap in your own upload, for example with dio's `onSendProgress`, and a
/// `CancelToken` to stop it.
Stream<double> fakeUpload(Photo photo) {
  final failAt = _random.nextDouble() < 0.3
      ? 0.2 + _random.nextDouble() * 0.6
      : null;
  final bytesPerTick = 75000 * (0.6 + _random.nextDouble() * 0.8);
  var sent = 0.0;
  Timer? timer;
  late final StreamController<double> controller;
  controller = StreamController(
    onListen: () {
      timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        sent = math.min(sent + bytesPerTick, photo.size.toDouble());
        if (failAt != null && sent >= photo.size * failAt) {
          timer!.cancel();
          controller
            ..addError(const UploadException('Connection lost'))
            ..close();
        } else {
          controller.add(sent / photo.size);
          if (sent == photo.size) {
            timer!.cancel();
            controller.close();
          }
        }
      });
    },
    onCancel: () => timer?.cancel(),
  );
  return controller.stream;
}
