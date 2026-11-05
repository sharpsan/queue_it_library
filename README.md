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

Pushing to `main` releases every package whose version isn't on pub.dev yet. To release one, bump
the version in its `pubspec.yaml`, add a matching section to its `CHANGELOG.md` and push to `main`.

Once CI passes, the Release workflow tags the commit (`queue_it-v0.10.0`,
`flutter_queue_it-v0.10.0`) and runs the Publish workflow on each tag, queue_it first. Publish
tests the package, publishes it to pub.dev and creates a GitHub release from its changelog.

If publishing fails, fix it and push to `main` again: a version that never made it to pub.dev
gets its tag moved to the new commit. Publish can also be run by hand on a release tag from the
Actions tab.
