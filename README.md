# queue_it_library

[![melos](https://img.shields.io/badge/maintained%20with-melos-f700ff.svg?style=flat-square)](https://github.com/invertase/melos)
[![Pub Version](https://img.shields.io/pub/v/queue_it?label=queue_it)](https://pub.dev/packages/queue_it)
[![Pub Version](https://img.shields.io/pub/v/flutter_queue_it?label=flutter_queue_it)](https://pub.dev/packages/flutter_queue_it)
[![codecov](https://codecov.io/gh/sharpsan/queue_it_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/queue_it_library)


This is a monorepo containing the following packages:

- [queue_it](https://github.com/sharpsan/queue_it_library/tree/main/queue_it): Queue handling with concurrency support for Dart.
- [flutter_queue_it](https://github.com/sharpsan/queue_it_library/tree/main/flutter_queue_it): Provides **QueueItWidget** that rebuilds when the queue changes.

Please check out each project for more details and examples.

## Development

The repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) managed with melos. It
needs Dart 3.9 or later, which means a current Flutter stable.

```sh
flutter pub get         # resolves both packages and both examples
dart run melos analyze  # or: flutter analyze
dart run melos test     # runs the tests of every package that has them
```

`melos format`, `melos run outdated` and `melos run upgrade` are also available. If melos is
activated globally (`dart pub global activate melos`), drop the `dart run`.
