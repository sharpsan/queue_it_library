# queue_it_library

[![CI](https://github.com/sharpsan/queue_it_library/actions/workflows/ci.yml/badge.svg)](https://github.com/sharpsan/queue_it_library/actions/workflows/ci.yml)
[![melos](https://img.shields.io/badge/maintained%20with-melos-f700ff.svg?style=flat-square)](https://github.com/invertase/melos)
[![Pub Version](https://img.shields.io/pub/v/queue_it?label=queue_it)](https://pub.dev/packages/queue_it)
[![Pub Version](https://img.shields.io/pub/v/flutter_queue_it?label=flutter_queue_it)](https://pub.dev/packages/flutter_queue_it)
[![codecov](https://codecov.io/gh/sharpsan/queue_it_library/graph/badge.svg?token=2YLWI5OLQ3)](https://codecov.io/gh/sharpsan/queue_it_library)


This is a monorepo containing the following packages:

- [queue_it](https://github.com/sharpsan/queue_it_library/tree/main/queue_it): Queue handling with concurrency support for Dart.
- [flutter_queue_it](https://github.com/sharpsan/queue_it_library/tree/main/flutter_queue_it): Provides **QueueItWidget**, which rebuilds when the queue changes, and **QueueItListener**, which calls back for every change.

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

The packages themselves support Dart 3.5 and Flutter 3.24. CI checks that by taking them out of
the workspace with `tool/leave_workspace.sh` and testing them on Flutter 3.24.5.

## Releasing

Pushing a tag publishes a package to pub.dev from GitHub Actions: `queue_it-v0.10.0` publishes
queue_it 0.10.0 and `flutter_queue_it-v0.10.0` publishes flutter_queue_it 0.10.0. The tag has to
match the version in the package's `pubspec.yaml`. The workflow tests the package and does a dry
run, then waits for approval in the `pub.dev` environment before it publishes.

```sh
git tag queue_it-v0.10.0
git push origin queue_it-v0.10.0
```

When flutter_queue_it needs a new queue_it, publish queue_it first. flutter_queue_it's run fails
until that queue_it is on pub.dev, and can be re-run once it is.
