#!/bin/sh
# Takes queue_it and flutter_queue_it out of the pub workspace, so they can be checked on their
# minimum SDK: the workspace itself needs Dart 3.9, for melos. It deletes the workspace files and
# the examples and edits the packages' pubspecs, so only run it in a throwaway copy of the
# repository, such as a CI checkout, from the copy's root. Uses GNU sed.
set -e
rm pubspec.yaml pubspec.lock
rm -r queue_it/example flutter_queue_it/example
# Any version of the dev dependencies that supports the SDK will do.
sed -i -E '/^resolution: workspace$/d; s/^(  (lints|flutter_lints|test|benchmark_harness)): .*/\1: any/' \
  queue_it/pubspec.yaml flutter_queue_it/pubspec.yaml
# flutter_queue_it gets this queue_it, not the one on pub.dev.
printf 'dependency_overrides:\n  queue_it:\n    path: ../queue_it\n' >> flutter_queue_it/pubspec.yaml
