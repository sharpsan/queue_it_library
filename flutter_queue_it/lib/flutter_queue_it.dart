/// Flutter integration for [queue_it](https://pub.dev/packages/queue_it).
///
/// [QueueItWidget] listens to a [QueueIt] queue and rebuilds whenever the
/// queue changes, so the UI can show the queue's items, progress and state.
/// [QueueItListener] calls back for every event without rebuilding.
///
/// This library exports `package:queue_it/queue_it.dart`, so it's the only
/// import you need.
library;

export 'package:queue_it/queue_it.dart';

export 'src/widgets/queue_it_listener.dart';
export 'src/widgets/queue_it_widget.dart';
